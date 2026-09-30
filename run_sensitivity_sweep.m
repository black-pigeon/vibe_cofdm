function results = run_sensitivity_sweep(snrDb,nFrames,outPath,options)
% v2 sensitivity characterization: fixed trials, paired RX, randomized phases.
% No true timing/channel/noise is supplied to the receiver. Truth only scores.
if nargin<1, snrDb=0:6; end
if nargin<2, nFrames=60; end
if nargin<3, outPath=''; end
if nargin<4, options=struct(); end
root=fileparts(mfilename('fullpath')); addpath(root);
if ~isfield(options,'seed'), options.seed=202609280; end
if ~isfield(options,'lengths'), options.lengths=1500; end
if ~isfield(options,'receivers')
    options.receivers={struct('name','compact','mode','compact','quantized',false)};
end
if ~isfield(options,'channels')
    options.channels={ ...
        struct('name','awgn','delays',0,'amplitudes',1,'cfoHz',0), ...
        struct('name','short','delays',[0 3 9],'amplitudes',[1 .25 .12],'cfoHz',135e3), ...
        struct('name','cp_edge','delays',[0 31],'amplitudes',[.65 1],'cfoHz',135e3)};
end
assert(isscalar(nFrames) && isfinite(nFrames) && nFrames>=1 && nFrames==floor(nFrames));
assert(isvector(snrDb) && all(isfinite(snrDb)));
txConfig=cofdm.config_v2('compact'); code=cofdm.ldpc_code();
configs=cell(size(options.receivers));
for m=1:numel(configs)
    item=options.receivers{m}; configs{m}=cofdm.config_v2(item.mode);
    configs{m}.quantizedDecoder=item.quantized;
    if isfield(item,'llrScale'), configs{m}.llrScale=item.llrScale; end
    if isfield(item,'syncThreshold'), configs{m}.syncThreshold=item.syncThreshold; end
    for field={'timingRelativeThreshold','timingNoiseMultiplier','timingMargin','timingWindowPlacement'}
        name=field{1}; if isfield(item,name), configs{m}.(name)=item.(name); end
    end
end
manifest=struct('complete',false,'matlabVersion',version,'options',options, ...
    'snrDb',snrDb,'framesPerPoint',nFrames,'txConfig',txConfig,'rxConfigs',{configs}, ...
    'snrDefinition','complex sample active-frame SNR; noise bandwidth Fs', ...
    'randomization','independent uniform path phases, CFO sign, offset 0..128 per capture', ...
    'seedRule','base + 100000*channelIndex + 10000*lengthIndex + 100*snrIndex');
write_manifest(outPath,manifest);
names={'channel','receiver','payload_bytes','sample_snr_db','frames','errors', ...
    'sync_failures','stf_failures','header_failures','payload_failures', ...
    'per','ci95_low','ci95_high','upper95','header_per_given_sync', ...
    'payload_per_given_header','unsafe_fft','cfo_rmse_hz','mean_ldpc_iterations', ...
    'slot_us','phy_goodput_mbps','rescues_vs_first','regressions_vs_first', ...
    'fusion_fast_updates','fusion_updates','channel_saturations', ...
    'rescues_vs_previous','regressions_vs_previous'};
results=table();
for a=1:numel(options.channels)
    scene=options.channels{a};
    for b=1:numel(options.lengths)
        length=options.lengths(b); layout=cofdm.frame_layout(txConfig,length);
        for j=1:numel(snrDb)
            cofdm.seed_rng(options.seed+100000*a+10000*b+100*j);
            % errors,sync,STF,header,payload,unsafe,CFO^2,iterations,words,rescue,regress
            counts=zeros(numel(configs),16);
            for k=1:nFrames
                payload=uint8(randi([0 255],length,1));
                wave=cofdm.tx(payload,0,txConfig,code);
                gains=scene.amplitudes.*exp(2j*pi*rand(size(scene.amplitudes)));
                p=struct('snrDb',snrDb(j),'cfoHz',scene.cfoHz*(2*randi([0 1])-1), ...
                    'offset',randi([0 128]),'delays',scene.delays,'gains',gains);
                if isfield(scene,'dopplerHz')
                    p.dopplerHz=scene.dopplerHz;
                    [y,truth]=cofdm.channel_timevarying(wave,txConfig,p);
                else
                    [y,truth]=cofdm.channel(wave,txConfig,p);
                end
                firstFailed=false; previousFailed=false;
                for m=1:numel(configs)
                    r=cofdm.rx(y,configs{m},code);
                    failed=~r.ok || ~isequal(r.payload,payload);
                    if m==1, firstFailed=failed; previousFailed=failed; end
                    counts(m,1)=counts(m,1)+failed;
                    counts(m,10)=counts(m,10)+(firstFailed && ~failed);
                    counts(m,11)=counts(m,11)+(~firstFailed && failed);
                    counts(m,15)=counts(m,15)+(previousFailed && ~failed);
                    counts(m,16)=counts(m,16)+(~previousFailed && failed);
                    previousFailed=failed;
                    if isfield(r,'fusionUpdates')
                        counts(m,12)=counts(m,12)+r.fusionFastUpdates;
                        counts(m,13)=counts(m,13)+r.fusionUpdates;
                    end
                    counts(m,14)=counts(m,14)+r.channelSaturations;
                    if ~r.sync.ok
                        counts(m,2)=counts(m,2)+1;
                        counts(m,3)=counts(m,3)+strcmp(r.sync.reason,'STF not found');
                    else
                        fftOffset=r.sync.ltfUsefulStart-(truth.frameStart+160+32);
                        unsafe=fftOffset<max(scene.delays)-32 || fftOffset>min(scene.delays);
                        counts(m,6)=counts(m,6)+unsafe;
                        counts(m,7)=counts(m,7)+(r.sync.cfoHz-p.cfoHz)^2;
                        if ~r.header.ok
                            counts(m,4)=counts(m,4)+1;
                        else
                            counts(m,5)=counts(m,5)+failed;
                        end
                    end
                    if isfield(r,'iterations')
                        counts(m,8)=counts(m,8)+sum(r.iterations);
                        counts(m,9)=counts(m,9)+numel(r.iterations);
                    end
                end
            end
            for m=1:numel(configs)
                q=counts(m,:); assert(q(1)==q(2)+q(4)+q(5));
                [lo,hi,upper]=cofdm.binomial_interval(q(1),nFrames);
                syncOk=nFrames-q(2); headerOk=syncOk-q(4);
                numeric=[length snrDb(j) nFrames q(1:5) q(1)/nFrames lo hi upper ...
                    divide(q(4),syncOk) divide(q(5),headerOk) q(6) ...
                    sqrt(divide(q(7),syncOk)) divide(q(8),q(9)) ...
                    layout.slotSamples/txConfig.fs*1e6 layout.netRate*(1-q(1)/nFrames)/1e6 q(10:16)];
                row=cell2table([{scene.name options.receivers{m}.name} num2cell(numeric)],'VariableNames',names);
                if isempty(results), results=row; else, results=[results;row]; end %#ok<AGROW>
                fprintf('%s %s L=%d SNR=%g errors=%d/%d sync/head/data=%d/%d/%d upper95=%.4f\n', ...
                    scene.name,options.receivers{m}.name,length,snrDb(j),q(1),nFrames,q(2),q(4),q(5),upper);
            end
            if ~isempty(outPath), writetable(results,outPath); end
        end
    end
end
manifest.complete=true; write_manifest(outPath,manifest);
end
function value=divide(a,b)
value=NaN; if b>0, value=a/b; end
end
function write_manifest(outPath,manifest)
if isempty(outPath), return; end
fid=fopen([outPath '.json'],'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(manifest));
end
