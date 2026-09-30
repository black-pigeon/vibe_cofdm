function [first,info] = choose_fft_window(score,lo,peakIndex,c)
% Reuse LTF correlation scores: no extra waveform correlations or truth.
% Thresholded local peaks approximate path support; not an oracle guarantee.
score=score(:); N=numel(score); ix=(1:N).';
off=abs(ix-peakIndex)>c.ncp;
noise=0; if any(off), noise=sum(score(off))/sum(off); end
threshold=max(c.timingRelativeThreshold*score(peakIndex), ...
    c.timingNoiseMultiplier*noise);
local=score>=[-Inf;score(1:end-1)] & score>=[score(2:end);-Inf];
paths=find(local & score>=threshold & abs(ix-peakIndex)<c.ncp);
paths=unique([paths;peakIndex]);
% Select the CP-sized cluster containing the strongest peak with most energy.
% Prefix/sliding sums need additions only, instead of summing every window.
weights=zeros(N,1); weights(paths)=score(paths);
prefix=[0;cumsum(weights)];
lefts=(max(1,peakIndex-c.ncp+1):peakIndex).';
rights=min(N,lefts+c.ncp-1);
energy=prefix(rights+1)-prefix(lefts);
[~,best]=max(energy);
selected=paths(paths>=lefts(best) & paths<=rights(best));
earliest=min(selected); latest=max(selected);
% Prefer an early FFT start, but do not exceed the estimated CP allowance.
window=max(earliest-c.timingMargin,latest-c.ncp+1);
if strcmp(c.timingWindowPlacement,'center')
    % Split the estimated CP slack between missed earlier and later paths.
    % Half-sum is an arithmetic shift in RTL; no new correlator or FFT.
    window=max(latest-c.ncp+1,floor((earliest+latest-c.ncp)/2));
else
    assert(strcmp(c.timingWindowPlacement,'early'));
end
window=max(1,window);
first=lo+window-1;
info=struct('threshold',threshold,'noiseFloor',noise, ...
    'pathOffsets',selected-peakIndex,'offsetFromPeak',window-peakIndex, ...
    'estimatedSafeOffsets',[latest-c.ncp+1 earliest]-peakIndex);
end
