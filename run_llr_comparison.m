function results = run_llr_comparison(snrDb,nFrames,outPath,seed)
% Shared-IQ LLR scaling ablation; 0.5 is a one-bit arithmetic right shift.
if nargin<1, snrDb=[3 4]; end
if nargin<2, nFrames=60; end
if nargin<3, outPath=''; end
if nargin<4, seed=202609295; end
options=struct('seed',seed,'lengths',1500);
scales=[1 .75 .5 .25]; names={'llr1','llr075','llr05','llr025'};
for k=1:numel(scales)
    options.receivers{k}=struct('name',names{k},'mode','compact_tracked', ...
        'quantized',false,'llrScale',scales(k));
end
options.channels={ ...
    struct('name','awgn','delays',0,'amplitudes',1,'cfoHz',0), ...
    struct('name','short','delays',[0 3 9],'amplitudes',[1 .25 .12],'cfoHz',135e3), ...
    struct('name','cp_edge','delays',[0 31],'amplitudes',[.65 1],'cfoHz',135e3)};
results=run_sensitivity_sweep(snrDb,nFrames,outPath,options);
end
