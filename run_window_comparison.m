function results = run_window_comparison(snrDb,nFrames,outPath,seed)
% Shared-IQ FFT-window ablation for CP-edge multipath.
if nargin<1, snrDb=[4 5 6]; end
if nargin<2, nFrames=60; end
if nargin<3, outPath=''; end
if nargin<4, seed=202609294; end
options=struct('seed',seed,'lengths',1500);
options.receivers={ ...
    struct('name','tracked_early','mode','compact_tracked','quantized',false,'timingRelativeThreshold',.04,'timingNoiseMultiplier',4,'timingMargin',2,'timingWindowPlacement','early'), ...
    struct('name','tracked_center','mode','compact_tracked','quantized',false,'timingRelativeThreshold',.04,'timingNoiseMultiplier',4,'timingMargin',2,'timingWindowPlacement','center'), ...
    struct('name','tracked_loose','mode','compact_tracked','quantized',false,'timingRelativeThreshold',.01,'timingNoiseMultiplier',2,'timingMargin',1,'timingWindowPlacement','center'), ...
    struct('name','tracked_relaxed','mode','compact_tracked','quantized',false,'timingRelativeThreshold',.02,'timingNoiseMultiplier',3,'timingMargin',1,'timingWindowPlacement','center')};
options.channels={struct('name','cp_edge','delays',[0 31],'amplitudes',[.65 1],'cfoHz',135e3)};
results=run_sensitivity_sweep(snrDb,nFrames,outPath,options);
end
