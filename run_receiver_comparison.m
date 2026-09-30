function rows = run_receiver_comparison(snrDb,nFrames,outPath,options)
% Paired ablation: identical payload, IQ, CFO and timing for every receiver.
% This is a static-channel experiment, not a mobility/sensitivity claim.
if nargin<1, snrDb=[4 6 8]; end
if nargin<2, nFrames=20; end
if nargin<3, outPath=''; end
if nargin<4, options=struct(); end
assert(nFrames>=1 && nFrames==floor(nFrames));
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config(); code=cofdm.ldpc_code(); seed=20260924;
if isfield(options,'seed'), seed=options.seed; end
if isfield(options,'quantizedDecoder'), c.quantizedDecoder=options.quantizedDecoder; end
cofdm.seed_rng(seed);
modes={'baseline','delay','delay_uncertainty','proposed'};
channels={struct('name','flat','delays',0,'gains',1), ...
    struct('name','short_multipath','delays',[0 3 9], ...
        'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]), ...
    struct('name','late_strong','delays',[0 10 23], ...
        'gains',[0.25 1 0.3*exp(0.7j)])};
if isfield(options,'modes'), modes=options.modes; end
if isfield(options,'channels'), channels=options.channels; end
rows=cell(0,20); fid=-1;
if ~isempty(outPath)
    fid=fopen(outPath,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'channel,receiver,sample_snr_db,frames,packet_errors,per,sync_fail_rate,header_fail_rate,conditional_payload_ber,mean_iterations,goodput_mbps,paired_rescues_minus_regressions,rescues,regressions,unsafe_fft_per_capture,seed,quantized_decoder,channel_saturations,rescues_vs_previous,regressions_vs_previous\n');
end
for a=1:numel(channels)
    for s=1:numel(snrDb)
        counts=zeros(numel(modes),9); success=false(nFrames,numel(modes));
        for f=1:nFrames
            payload=uint8(randi([0 255],c.payloadBytes,1));
            wave=cofdm.tx(payload,mod(f,65536),c,code);
            p=channels{a}; p.snrDb=snrDb(s);
            if ~isfield(p,'cfoHz'), p.cfoHz=135e3; end
            if ~isfield(p,'offset'), p.offset=37; end
            if isfield(p,'randomizePhases') && p.randomizePhases
                p.gains=abs(p.gains).*exp(2j*pi*rand(size(p.gains)));
            end
            [y,truth]=cofdm.channel(wave,c,p);
            for m=1:numel(modes)
                rc=cofdm.receiver_config(c,modes{m}); r=cofdm.rx(y,rc,code);
                success(f,m)=r.ok && isequal(r.payload,payload);
                counts(m,1)=counts(m,1)+~success(f,m);
                counts(m,2)=counts(m,2)+~r.sync.ok;
                counts(m,3)=counts(m,3)+(r.sync.ok && isempty(r.payload));
                counts(m,9)=counts(m,9)+r.channelSaturations;
                if r.sync.ok
                    % Truth is used only for post-reception diagnostic scoring.
                    delta=r.sync.ltfUsefulStart-(truth.frameStart+c.stfPeriod*c.stfRepeats+c.ncp);
                    unsafe=delta>min(p.delays) || delta<max(p.delays)-c.ncp;
                    counts(m,8)=counts(m,8)+unsafe;
                end
                if ~isempty(r.payload)
                    counts(m,4)=counts(m,4)+sum(cofdm.bytes_to_bits(payload)~=cofdm.bytes_to_bits(r.payload));
                    counts(m,5)=counts(m,5)+8*numel(payload);
                    counts(m,6)=counts(m,6)+sum(r.iterations);
                    counts(m,7)=counts(m,7)+numel(r.iterations);
                end
            end
        end
        for m=1:numel(modes)
            ber=NaN; mi=NaN;
            if counts(m,5)>0, ber=counts(m,4)/counts(m,5); end
            if counts(m,7)>0, mi=counts(m,6)/counts(m,7); end
            per=counts(m,1)/nFrames;
            rescues=sum(success(:,m) & ~success(:,1));
            regressions=sum(~success(:,m) & success(:,1)); net=rescues-regressions;
            previous=max(1,m-1);
            recoveredPrevious=sum(success(:,m) & ~success(:,previous));
            regressedPrevious=sum(~success(:,m) & success(:,previous));
            row={channels{a}.name,modes{m},snrDb(s),nFrames,counts(m,1),per, ...
                counts(m,2)/nFrames,counts(m,3)/nFrames,ber,mi,c.netRate*(1-per)/1e6,net, ...
                rescues,regressions,counts(m,8)/nFrames,seed,c.quantizedDecoder, ...
                counts(m,9),recoveredPrevious,regressedPrevious};
            rows(end+1,:)=row; %#ok<AGROW>
            fprintf('%s SNR %g %s PER %.3f mean_iter %.2f paired_net %+d\n', ...
                row{1},snrDb(s),row{2},per,mi,net);
            if fid>=0
                fprintf(fid,'%s,%s,%.8g,%d,%d,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g,%d,%d,%d,%.8g,%d,%d,%d,%d,%d\n',row{:});
            end
        end
    end
end
if ~isempty(outPath)
    metadata=struct('seed',seed,'framesPerPoint',nFrames,'snrDb',snrDb, ...
        'timingNoiseStatistic','off-peak arithmetic mean');
    for m=1:numel(modes)
        metadata.receivers.(modes{m})=cofdm.receiver_config(c,modes{m});
    end
    for a=1:numel(channels)
        ch=channels{a};
        metadata.channels(a).name=ch.name;
        metadata.channels(a).delays=ch.delays;
        metadata.channels(a).gainsReal=real(ch.gains);
        metadata.channels(a).gainsImag=imag(ch.gains);
        metadata.channels(a).cfoHz=135e3; metadata.channels(a).offset=37;
        metadata.channels(a).randomizePhases=false;
        if isfield(ch,'randomizePhases'), metadata.channels(a).randomizePhases=ch.randomizePhases; end
        if isfield(ch,'cfoHz'), metadata.channels(a).cfoHz=ch.cfoHz; end
        if isfield(ch,'offset'), metadata.channels(a).offset=ch.offset; end
    end
    metaFile=fopen([outPath '.json'],'w'); assert(metaFile>=0);
    metaCleanup=onCleanup(@()fclose(metaFile));
    fprintf(metaFile,'%s\n',jsonencode(metadata));
end
end
