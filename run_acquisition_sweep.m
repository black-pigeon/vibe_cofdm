function rows = run_acquisition_sweep(outPath)
% Compare acquisition thresholds using held-out seeds and noise-only captures.
% Small engineering screen, not a continuous-stream false alarm qualification.
if nargin<1, outPath=''; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config(); code=cofdm.ldpc_code();
cofdm.seed_rng(c.seed+100);
payload=uint8(randi([0 255],c.payloadBytes,1));
wave=cofdm.tx(payload,19,c,code);
thresholds=[0.40 0.65]; levels=[0 2 4 6 8]; trials=40; noiseTrials=200;
rows=[];
for q=1:numel(thresholds)
    c.syncThreshold=thresholds(q);
    for j=1:numel(levels)
        cofdm.seed_rng(c.seed+1000+j); % identical channel/noise per threshold
        success=0; accurate=0;
        for f=1:trials
            p=struct('snrDb',levels(j),'cfoHz',135e3,'offset',37, ...
                'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
            [y,t]=cofdm.channel(wave,c,p); s=cofdm.synchronize(y,c);
            success=success+s.ok;
            accurate=accurate+(s.ok && abs(s.frameStart-t.frameStart)<=1 && abs(s.cfoHz-p.cfoHz)<1500);
        end
        rows(end+1,:)=[thresholds(q),levels(j),trials,success/trials,accurate/trials]; %#ok<AGROW>
        fprintf('Threshold %.2f SNR %.1f acquisition %.3f accurate %.3f\n', ...
            thresholds(q),levels(j),success/trials,accurate/trials);
    end
    cofdm.seed_rng(c.seed+9000); falseAlarms=0;
    for f=1:noiseTrials
        y=randn(c.slotSamples,1)+1j*randn(c.slotSamples,1);
        s=cofdm.synchronize(y,c); falseAlarms=falseAlarms+s.ok;
    end
    fprintf('Threshold %.2f noise-only false acceptance %d/%d captures\n',thresholds(q),falseAlarms,noiseTrials);
    rows(end+1,:)=[thresholds(q),NaN,noiseTrials,falseAlarms/noiseTrials,NaN]; %#ok<AGROW>
end
if ~isempty(outPath)
    fid=fopen(outPath,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
    fprintf(fid,'threshold,sample_snr_db,captures,acquisition_or_noise_accept_rate,accurate_acquisition_rate\n');
    fprintf(fid,'%.8g,%.8g,%d,%.8g,%.8g\n',rows.');
end
end
