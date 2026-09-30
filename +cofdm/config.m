function c = config()
% CONFIG Self-contained SISO COFDM v0.1 profile; all rates in Hz.
c.fs = 15.36e6;
c.nfft = 256;
c.ncp = 32;
c.active = [-100:-1 1:100].';
c.pilots = [-91 -65 -39 -13 13 39 65 91].';
c.data = setdiff(c.active, c.pilots);
c.activeBins = mod(c.active,c.nfft)+1; % unshifted MATLAB FFT bins
c.pilotBins = mod(c.pilots,c.nfft)+1;
c.dataBins = mod(c.data,c.nfft)+1;
[~,c.pilotInActive] = ismember(c.pilots,c.active);
[~,c.dataInActive] = ismember(c.data,c.active);
c.zcLength = 201; c.zcRoots = [25 29]; % remove center element for DC
c.stfPeriod = 16; c.stfRepeats = 10;
c.txScale = 0.25;
c.nCodewords = 16; c.ldpcN = 648; c.ldpcK = 324;
c.bitsPerSymbol = 2*numel(c.data);
c.nDataSymbols = c.nCodewords*c.ldpcN/c.bitsPerSymbol;
assert(c.nDataSymbols == floor(c.nDataSymbols));
c.midambleEvery = 8;
c.nMidambles = floor((c.nDataSymbols-1)/c.midambleEvery);
c.nHeaderSymbols = ceil(c.ldpcN/numel(c.data)); % BPSK, padded after FEC
c.payloadBytes = (c.nCodewords*c.ldpcK-32)/8;
c.guardSamples = 32;
c.frameSamples = c.stfPeriod*c.stfRepeats + ...
    (2+c.nHeaderSymbols+c.nDataSymbols+c.nMidambles)*(c.nfft+c.ncp);
c.slotSamples = c.frameSamples+c.guardSamples;
c.netRate = c.payloadBytes*8*c.fs/c.slotSamples;
c.profile = 1; c.version = 1; c.scramblerSeed = 93;
c.variablePayload = false;
c.headerScramblerSeed = 31;
c.interleaver = mod(13*(0:c.bitsPerSymbol-1),c.bitsPerSymbol)+1;
c.ldpcIterations = 12; c.ldpcAlpha = 0.75;
c.quantizedDecoder = false;
c.trackPhaseSlope = true;
% Keep the original receiver as the reproducible default. See receiver_config.
c.channelEstimator = 'ls';
c.channelErrorAwareLLR = false;
c.pilotTracker = 'unwrap';
% Relative to strongest-path timing: allow paths on either side within CP.
c.delaySupport = (-c.ncp+1:c.ncp-1).';
c.phaseSlopeStd = 2*pi/c.nfft/8; % prior: 1/8 sample, experimental
c.phaseSlopeMax = 2*pi/c.nfft;   % search: +/-1 sample relative to current H
c.pilotSlopeCandidates = 33;
c.fftWindowMode = 'peak';
c.timingRelativeThreshold = 0.04;
c.timingNoiseMultiplier = 4;
c.timingMargin = 2;
c.smoothingCenterDelay = c.ncp/2;
c.timingWindowPlacement = 'early';
c.fixedChannel = false;
c.quantizedPilotRom = false;
c.channelFusion = false;
c.channelFusionFixed = false;
c.channelFusionShift = 2; % alpha=1/4; innovation gate selects alpha=1
c.channelInnovationFactor = 4;
c.channelFusionPhase = 'quadrant'; % four rotations; no atan2/CORDIC
c.llrScale = 1; % power-of-two candidate 1/2 maps to arithmetic right shift
c.temporalPilots = false;
c.pilotTemporalAlpha = 1/2;
c.pilotTemporalBeta = 1/16;
c.channelWordBits = 18; c.channelFractionBits = 14;
c.coefficientWordBits = 18; c.coefficientFractionBits = 16;
c.channelAccumulatorBits = 26;
c.syncThreshold = 0.40; c.syncMinRun = 24;
c.syncPeakThreshold = 0.12;
c.seed = 20260923;
end
