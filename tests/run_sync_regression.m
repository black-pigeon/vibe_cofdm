function report = run_sync_regression(outDir, opts)
%RUN_SYNC_REGRESSION Unified MATLAB regression for the acquisition front end.
%
% The test deliberately measures the same events that exist in the FPGA
% capture controller: STF detection, LTF capture, coarse CFO, fine CFO and
% final frame lock.  It also exports one deterministic IQ capture as a golden
% vector for RTL/XFFT co-simulation.
%
%   report = run_sync_regression();
%   report = run_sync_regression('matlab/results/sync_regression', ...
%                                struct('trials',50,'noiseTrials',500));

root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
if nargin<1 || isempty(outDir), outDir=fullfile(root,'results','sync_regression'); end
if nargin<2 || isempty(opts), opts=struct(); end
trials=option(opts,'trials',20);
noiseTrials=option(opts,'noiseTrials',100);
exportGolden=option(opts,'exportGolden',true);
assert(isscalar(trials) && trials==floor(trials) && trials>0);
assert(isscalar(noiseTrials) && noiseTrials==floor(noiseTrials) && noiseTrials>0);
if ~exist(outDir,'dir'), mkdir(outDir); end

profile=option(opts,'profile','v1');
if strcmp(profile,'v2'), c=cofdm.config_v2(); else
    assert(strcmp(profile,'v1')); c=cofdm.config();
end
code=cofdm.ldpc_code();
% One fixed payload makes each scenario comparable while channel noise remains
% independently seeded for every trial.
cofdm.seed_rng(c.seed+1700);
if c.variablePayload, payloadBytes=511; seq=0; else, payloadBytes=c.payloadBytes; seq=41; end
payload=uint8(randi([0 255],payloadBytes,1));
[wave,~]=cofdm.tx(payload,seq,c,code);

scenarios(1)=struct('name','noiseless','snrDb',Inf,'cfoHz',0,'offset',0,...
    'delays',0,'gains',1);
scenarios(2)=struct('name','awgn_cfo','snrDb',20,'cfoHz',135e3,'offset',37,...
    'delays',0,'gains',1);
scenarios(3)=struct('name','multipath','snrDb',18,'cfoHz',-220e3,'offset',83,...
    'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
scenarios(4)=struct('name','low_snr','snrDb',8,'cfoHz',65e3,'offset',11,...
    'delays',[0 2 7],'gains',[1 0.35*exp(-0.3j) 0.10j]);

rows=cell(numel(scenarios),1);
for q=1:numel(scenarios)
    p=scenarios(q);
    stf=0; ltf=0; lock=0; cp=0; timeout=0;
    coarseErr=[]; fineErr=[]; finalErr=[]; posErr=[];
    for k=1:trials
        cofdm.seed_rng(c.seed+3000+100*q+k);
        [y,truth]=cofdm.channel(wave,c,p);
        s=cofdm.synchronize(y,c);
        stf=stf+double(s.stfDetected);
        ltf=ltf+double(s.ltfDetected);
        lock=lock+double(s.ok);
        timeout=timeout+double(s.stfDetected && ~s.ok);
        if s.stfDetected && isfinite(s.coarseCfoHz)
            coarseErr(end+1)=s.coarseCfoHz-p.cfoHz; %#ok<AGROW>
        end
        if s.ltfDetected && isfinite(s.fineCfoHz)
            fineErr(end+1)=s.fineCfoHz-(p.cfoHz-s.coarseCfoHz); %#ok<AGROW>
        end
        if s.ok
            finalErr(end+1)=s.cfoHz-p.cfoHz; %#ok<AGROW>
            posErr(end+1)=s.frameStart-truth.frameStart; %#ok<AGROW>
            % Safe FFT start: latest path minus CP <= start <= earliest path.
            useful=truth.frameStart+c.stfPeriod*c.stfRepeats+c.ncp;
            delta=s.ltfUsefulStart-useful;
            cp=cp+double(delta>=max(p.delays)-c.ncp && delta<=min(p.delays));
        end
    end
    rows{q}=make_row(p,trials,stf,ltf,lock,cp,timeout,coarseErr,fineErr,...
        finalErr,posErr,NaN);
    fprintf(['SYNC %-12s STF %.3f LTF %.3f lock %.3f CP %.3f ', ...
        'CFO(final) RMSE %.1f Hz pos RMSE %.3f samples\n'],p.name,...
        rows{q}.stf_detection_rate,rows{q}.ltf_capture_rate,...
        rows{q}.sync_success_rate,rows{q}.cp_window_rate,...
        rows{q}.final_cfo_rmse_hz,rows{q}.position_rmse_samples);
end

% Noise-only captures exercise the complete decision chain and quantify false
% acceptance.  A periodic complex tone is also checked because it can trigger
% an STF comb metric without being a valid LTF.
cofdm.seed_rng(c.seed+9000); falseAlarms=0; toneAccepts=0;
for k=1:noiseTrials
    y=randn(c.slotSamples,1)+1j*randn(c.slotSamples,1);
    s=cofdm.synchronize(y,c); falseAlarms=falseAlarms+double(s.ok);
    tone=exp(1j*2*pi*0.031*(0:c.slotSamples-1).');
    tone=tone+0.02*(randn(size(tone))+1j*randn(size(tone)));
    s=cofdm.synchronize(tone,c); toneAccepts=toneAccepts+double(s.ok);
end
noiseRow=struct('scenario','noise_only','trials',noiseTrials,...
    'snr_db',NaN,'true_cfo_hz',NaN,'stf_detection_rate',NaN,...
    'ltf_capture_rate',NaN,'sync_success_rate',falseAlarms/noiseTrials,...
    'cp_window_rate',NaN,'coarse_cfo_rmse_hz',NaN,'fine_cfo_rmse_hz',NaN,...
    'final_cfo_rmse_hz',NaN,'position_bias_samples',NaN,...
    'position_rmse_samples',NaN,'false_alarm_rate',falseAlarms/noiseTrials,...
    'periodic_tone_accept_rate',toneAccepts/noiseTrials,'candidate_reject_rate',NaN);
rows{end+1}=noiseRow;
fprintf('SYNC noise-only false acceptance %d/%d (%.4g), periodic-tone %.4g\n',...
    falseAlarms,noiseTrials,noiseRow.false_alarm_rate,noiseRow.periodic_tone_accept_rate);

report=struct('config',c,'trials',trials,'noiseTrials',noiseTrials,...
    'rows',{rows},'generated',datestr(now,31));
write_report_csv(fullfile(outDir,'sync_regression.csv'),rows);
save(fullfile(outDir,'sync_regression.mat'),'report','-v7');

if exportGolden
    % Deterministic representative capture.  The MAT file retains complex
    % doubles for MATLAB checks; the CSV is convenient for a testbench or
    % Python/Vivado preprocessing script.
    p=scenarios(2); cofdm.seed_rng(c.seed+4242);
    [y,truth]=cofdm.channel(wave,c,p); s=cofdm.synchronize(y,c);
    golden=struct('rx_iq',y,'payload',payload,'truth',truth,'sync',s,...
        'scenario',p,'fs',c.fs,'nfft',c.nfft,'ncp',c.ncp);
    % Quantized input has its own floating-point oracle; it is not a
    % bit-accurate RTL CFO/matcher oracle. Saturation is forbidden here.
    iq=round([real(y) imag(y)]*2^15);
    assert(all(abs(iq(:))<32768),'Golden IQ clips Q1.15');
    quantized=complex(iq(:,1),iq(:,2))/2^15;
    golden.quantizedSync=cofdm.synchronize(quantized,c);
    fidq=fopen(fullfile(outDir,'sync_golden_iq_s16.mem'),'w'); assert(fidq>=0);
    fprintf(fidq,'%04x%04x\n',mod(iq(:,[2 1]),65536).'); fclose(fidq);
    save(fullfile(outDir,'sync_golden.mat'),'golden','-v7');
    write_iq_csv(fullfile(outDir,'sync_golden_iq.csv'),y);
    fid=fopen(fullfile(outDir,'sync_golden_expected.csv'),'w'); assert(fid>=0);
    cl=onCleanup(@()fclose(fid));
    fprintf(fid,'stf_detected,stf_start,ltf_detected,ltf_peak_start,frame_start,coarse_cfo_hz,fine_cfo_hz,final_cfo_hz,ltf_peak\n');
    fprintf(fid,'%d,%.0f,%d,%.0f,%.0f,%.9g,%.9g,%.9g,%.9g\n',...
        s.stfDetected,s.stfStart,s.ltfDetected,s.ltfPeakStart,s.frameStart,...
        s.coarseCfoHz,s.fineCfoHz,s.cfoHz,s.peak);
end
% Deterministic engineering regression gates, not sensitivity qualification.
assert(rows{1}.sync_success_rate==1 && rows{1}.final_cfo_rmse_hz<1);
for q=2:numel(scenarios)
    assert(rows{q}.sync_success_rate>=0.90 && rows{q}.cp_window_rate>=0.90);
    assert(rows{q}.final_cfo_rmse_hz<1500);
end
assert(falseAlarms==0 && toneAccepts==0);
fprintf('PASS synchronization regression (%s); no Header CRC lock tested here\n',profile);
end

function value=option(s,name,default)
if isfield(s,name) && ~isempty(s.(name)), value=s.(name); else, value=default; end
end

function r=make_row(p,N,stf,ltf,lock,cp,timeout,coarse,fine,final,pos,falseRate)
r=struct('scenario',p.name,'trials',N,'snr_db',p.snrDb,...
    'true_cfo_hz',p.cfoHz,'stf_detection_rate',stf/N,...
    'ltf_capture_rate',ltf/N,'sync_success_rate',lock/N,...
    'cp_window_rate',cp/N,'coarse_cfo_rmse_hz',rmse(coarse),...
    'fine_cfo_rmse_hz',rmse(fine),'final_cfo_rmse_hz',rmse(final),...
    'position_bias_samples',mean_or_nan(pos),'position_rmse_samples',rmse(pos),...
    'false_alarm_rate',falseRate,'periodic_tone_accept_rate',NaN,...
    'candidate_reject_rate',timeout/N);
end

function v=rmse(x)
if isempty(x), v=NaN; else, v=sqrt(mean(double(x).^2)); end
end

function v=mean_or_nan(x)
if isempty(x), v=NaN; else, v=mean(double(x)); end
end

function write_report_csv(path,rows)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,['scenario,trials,snr_db,true_cfo_hz,stf_detection_rate,',...
    'ltf_capture_rate,sync_success_rate,cp_window_rate,coarse_cfo_rmse_hz,',...
    'fine_cfo_rmse_hz,final_cfo_rmse_hz,position_bias_samples,',...
    'position_rmse_samples,false_alarm_rate,periodic_tone_accept_rate,candidate_reject_rate\n']);
for k=1:numel(rows)
    r=rows{k};
    fprintf(fid,'%s,%d,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g\n',...
        r.scenario,r.trials,r.snr_db,r.true_cfo_hz,r.stf_detection_rate,...
        r.ltf_capture_rate,r.sync_success_rate,r.cp_window_rate,...
        r.coarse_cfo_rmse_hz,r.fine_cfo_rmse_hz,r.final_cfo_rmse_hz,...
        r.position_bias_samples,r.position_rmse_samples,r.false_alarm_rate,...
        r.periodic_tone_accept_rate,r.candidate_reject_rate);
end
end

function write_iq_csv(path,y)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,'sample,i,q\n');
idx=(0:numel(y)-1).';
fprintf(fid,'%.0f,%.17g,%.17g\n',[idx real(y(:)) imag(y(:))].');
end
