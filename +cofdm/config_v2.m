function c = config_v2(mode)
% Experimental variable-length PHY; receiver never needs actual TX length.
if nargin<1, mode='compact'; end
c=cofdm.receiver_config(cofdm.config(),mode);
c.version=2; c.profile=0; % MCS 0: QPSK, LDPC(648,324), rate 1/2
c.variablePayload=true; c.maxPayloadBytes=2048;
c.nHeaderSymbols=1; c.midambleCode=0; c.midambleEvery=8;
% Only the acquisition/header prefix is known before decoding PHY header.
c.payloadBytes=0; c.nCodewords=0; c.nDataSymbols=0; c.nMidambles=0;
c.frameSamples=c.stfPeriod*c.stfRepeats+(2+c.nHeaderSymbols)*(c.nfft+c.ncp);
c.slotSamples=c.frameSamples+c.guardSamples; c.netRate=0;
c.symbolPadSeed=47;
end
