function b = receiver_budget()
% Algorithm operation/storage bounds, NOT synthesis or timing estimates.
c=cofdm.config(); n=numel(c.active); rank=numel(c.delaySupport);
updates=1+c.nMidambles; tracked=c.nHeaderSymbols+c.nDataSymbols;
slot=c.slotSamples/c.fs;
b.projectionComplexMacPerUpdate=2*n*rank;
b.firComplexMultiplyPerUpdate=2*n; % pre/post rotations, conservative
b.firComplexAddPerUpdate=9*n; % symmetric 7-tap shift/add structure
b.projectionComplexMacPerFrame=updates*b.projectionComplexMacPerUpdate;
b.firComplexMultiplyPerFrame=updates*b.firComplexMultiplyPerUpdate;
b.projectionRate=b.projectionComplexMacPerFrame/slot;
b.firRotationRate=b.firComplexMultiplyPerFrame/slot;
b.searchComplexMacPerFrame=[33 9]*numel(c.pilots)*tracked;
% Both exclude common pilot correlations, final phi, data phase rotation,
% reciprocals, noise estimation, FFT, LDPC and acquisition.
b.projectionBasisBits=n*rank*32; % complex coefficients, 16 bits/component
b.firRotationRomBits=16*32; % centerDelay=16 => only 16 distinct phases
b.firNormalizationRomBits=n*2*16; % reciprocals and noise gains; not compressed
b.pilotSearchRomBits=[33 9]*numel(c.pilots)*32;
b.scoreBufferBits=193*24; % assumption only; no score quantization implemented
b.fixedRotationRomBits=16*2*c.coefficientWordBits;
b.fixedNormalizationRomBits=201*c.coefficientWordBits;
b.fixedPilotRomBits=9*numel(c.pilots)*2*c.coefficientWordBits;
b.fixedFirStateBits=6*2*c.channelWordBits;
b.fusionPilotComplexMacPerMid=numel(c.pilots);
b.fusionBlendComplexShiftPerMid=numel(c.active);
b.fusionStateBits=2*numel(c.active)*c.channelWordBits;
b.temporalPilotStateBits=2*32;
fprintf('Channel projection: %d complex MAC/update, %.3f M MAC/s\n', ...
    b.projectionComplexMacPerUpdate,b.projectionRate/1e6);
fprintf('FIR7: <=%d complex rotations + %d complex adds/update, %.3f M rotations/s\n', ...
    b.firComplexMultiplyPerUpdate,b.firComplexAddPerUpdate,b.firRotationRate/1e6);
fprintf('Pilot scan: %d -> %d complex MAC/frame (search only)\n',b.searchComplexMacPerFrame);
fprintf('Channel basis ROM %d bits; FIR rotation+normalization ROM <=%d bits\n', ...
    b.projectionBasisBits,b.firRotationRomBits+b.firNormalizationRomBits);
fprintf('Counts exclude shared receiver work; do not translate directly to DSP/BRAM utilization.\n');
fprintf('Actual fixed candidate: rotation/normalization/pilot ROM %d/%d/%d bits; FIR delay state %d bits\n', ...
    b.fixedRotationRomBits,b.fixedNormalizationRomBits,b.fixedPilotRomBits,b.fixedFirStateBits);
fprintf('Centered window adds half-sum/compare only; complex-MAC count unchanged.\n');
fprintf('Fusion candidate: %d pilot complex MAC + %d quadrant/shift updates per MID; state <=%d bits.\n', ...
    b.fusionPilotComplexMacPerMid,b.fusionBlendComplexShiftPerMid,b.fusionStateBits);
fprintf('Pilot temporal tracker adds <=%d state bits; gains 1/2 and 1/16 are shifts.\n',b.temporalPilotStateBits);
end
