function [bits,ok] = header_viterbi(llr)
% Soft ML Viterbi, positive LLR -> bit 0; known initial and terminal state 0.
llr=double(llr(:)); bits=false(48,1); ok=false;
if numel(llr)~=108 || any(~isfinite(llr)), return; end
t=cofdm.header_trellis(); metric=-Inf(64,1); metric(1)=0;
survivor=zeros(64,54,'uint8');
states=(0:63).'; inputs=floor(states/32); prev0=2*mod(states,32); prev1=prev0+1;
idx0=sub2ind([64 2],prev0+1,inputs+1); idx1=sub2ind([64 2],prev1+1,inputs+1);
o1=t.output(:,:,1); o2=t.output(:,:,2);
for k=1:54
    a=metric(prev0+1)+(1-2*double(o1(idx0)))*llr(2*k-1)+(1-2*double(o2(idx0)))*llr(2*k);
    b=metric(prev1+1)+(1-2*double(o1(idx1)))*llr(2*k-1)+(1-2*double(o2(idx1)))*llr(2*k);
    take1=b>a; metric=max(a,b); metric=metric-max(metric);
    survivor(:,k)=uint8(prev0+double(take1));
end
state=0; decoded=false(54,1);
for k=54:-1:1
    decoded(k)=state>=32; state=double(survivor(state+1,k));
end
bits=decoded(1:48); ok=state==0 && ~any(decoded(49:end));
% CRC and field validation remain mandatory: Viterbi always finds a path.
end
