function [Y,phi,slope,state] = track_pilots(Y,H,nv,channelVariance,c,index,state)
% Baseline unwrap-WLS or bounded circular MAP fit (no phase unwrapping).
if nargin<7, state=[]; end
p=c.pilotInActive; xp=cofdm.pilot_values(c,index);
e=Y(p).*conj(H(p).*xp); w=abs(H(p)).^2;
if strcmp(c.pilotTracker,'circular')
    e=e./max(nv+channelVariance(p),1e-12);
    slopes=0;
    if c.trackPhaseSlope
        slopes=linspace(-c.phaseSlopeMax,c.phaseSlopeMax,c.pilotSlopeCandidates);
    end
    searchRom=exp(-1j*c.pilots*slopes);
    if c.quantizedPilotRom
        searchRom=cofdm.quantize_signed(searchRom,c.coefficientWordBits,c.coefficientFractionBits);
    end
    objective=2*abs(e.'*searchRom) ...
        -0.5*(slopes/c.phaseSlopeStd).^2;
    [~,j]=max(objective); slope=slopes(j);
    if j>1 && j<numel(slopes)
        q=objective(j-1:j+1); den=q(1)-2*q(2)+q(3);
        if den < -eps
            delta=max(-0.5,min(0.5,0.5*(q(1)-q(3))/den));
            slope=slope+delta*(slopes(2)-slopes(1));
        end
    end
    phi=angle(sum(e.*exp(-1j*c.pilots*slope)));
elseif strcmp(c.pilotTracker,'unwrap')
    if c.trackPhaseSlope && sum(w)>1e-12
        a=unwrap(angle(e)); A=[ones(numel(p),1),c.pilots];
        theta=(A'*bsxfun(@times,A,w)+1e-9*eye(2))\(A'*(w.*a));
        phi=theta(1); slope=theta(2);
    else
        phi=angle(sum(e)); slope=0;
    end
else
    error('Unknown pilot tracker: %s',c.pilotTracker);
end
if c.temporalPilots
    if isempty(state)
        state=struct('phase',phi,'frequency',0,'index',index);
    else
        gap=index-state.index; assert(gap==1 || gap==2);
        predicted=state.phase+gap*state.frequency;
        phaseErr=wrap(phi-predicted);
        if abs(phaseErr)>pi/2
            % Reacquire a large phase step; normal operation is shift/add.
            state.phase=phi; state.frequency=0;
        else
            state.phase=wrap(predicted+c.pilotTemporalAlpha*phaseErr);
            state.frequency=state.frequency+c.pilotTemporalBeta*phaseErr/gap;
        end
        state.index=index;
    end
    phi=state.phase;
end
Y=Y.*exp(-1j*(phi+slope*c.active));
end
function phase=wrap(phase)
phase=mod(phase+pi,2*pi)-pi;
end
