function c = frame_layout(c,payloadBytes)
% Derive bounded per-frame counters only after validating length / profile.
assert(c.version==2 && c.variablePayload && c.profile==0,'Unsupported v2 profile');
assert(isscalar(payloadBytes) && isfinite(payloadBytes) && payloadBytes==floor(payloadBytes));
assert(payloadBytes>=1 && payloadBytes<=min(c.maxPayloadBytes,2048),'Invalid payload length');
assert(c.midambleCode>=0 && c.midambleCode<=2 && c.midambleCode==floor(c.midambleCode));
assert(c.scramblerSeed>=1 && c.scramblerSeed<=127 && c.scramblerSeed==floor(c.scramblerSeed));
periods=[8 4 16]; c.midambleEvery=periods(c.midambleCode+1);
c.payloadBytes=payloadBytes;
c.nCodewords=ceil((8*payloadBytes+32)/c.ldpcK);
c.nDataSymbols=ceil(c.nCodewords*c.ldpcN/c.bitsPerSymbol);
c.nMidambles=floor((c.nDataSymbols-1)/c.midambleEvery);
c.infoPadBits=c.nCodewords*c.ldpcK-(8*payloadBytes+32);
c.codedPadBits=c.nDataSymbols*c.bitsPerSymbol-c.nCodewords*c.ldpcN;
c.frameSamples=c.stfPeriod*c.stfRepeats+ ...
    (2+c.nHeaderSymbols+c.nDataSymbols+c.nMidambles)*(c.nfft+c.ncp);
c.slotSamples=c.frameSamples+c.guardSamples;
c.netRate=8*payloadBytes*c.fs/c.slotSamples;
end
