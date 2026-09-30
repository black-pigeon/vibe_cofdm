function [H,variance,d] = fuse_channel(old,oldVariance,fresh,freshVariance,c,pilotIndex)
% Causal MID update. Remove common phase before a shift/add IIR blend.
% Variance models observation noise, NOT full bias / Doppler / phase error.
if nargin<6, pilotIndex=1:numel(old); end
% Only eight pilot tones are needed for phase quadrant and innovation gate;
% the full 200-tone vector is blended with sign/swap and shifts below.
cross=sum(fresh(pilotIndex).*conj(old(pilotIndex)));
if strcmp(c.channelFusionPhase,'quadrant')
    % Pick one of {1,-j,-1,j}; compare only abs(Re/Im). This is
    % sign/swap logic in RTL, with no CORDIC, divider or multiplier.
    if abs(real(cross))>=abs(imag(cross))
        if real(cross)>=0, rot=1; else, rot=-1; end
    else
        if imag(cross)>=0, rot=-1j; else, rot=1j; end
    end
    aligned=fresh*rot; phase=0;
else
    phase=angle(cross); aligned=fresh*exp(-1j*phase);
end
difference=fresh(pilotIndex)-old(pilotIndex);
d=struct('phase',phase,'fast',false,'innovation',sum(abs(difference).^2), ...
    'saturations',0);
threshold=c.channelInnovationFactor*sum(oldVariance+freshVariance);
d.fast=d.innovation>threshold;
if c.channelFusionFixed
    [aligned,n]=cofdm.quantize_signed(aligned,c.channelWordBits,c.channelFractionBits);
    d.saturations=d.saturations+n;
end
alpha=2^(-c.channelFusionShift); if d.fast, alpha=1; end
H=old+alpha*(aligned-old);
if c.channelFusionFixed
    [H,n]=cofdm.quantize_signed(H,c.channelWordBits,c.channelFractionBits);
    d.saturations=d.saturations+n;
end
variance=(1-alpha)^2*oldVariance+alpha^2*freshVariance;
end
