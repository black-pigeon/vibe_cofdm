function c = receiver_config(c,mode)
% Receiver-only ablations, identical waveform in every mode.
c.channelEstimator='ls'; c.channelErrorAwareLLR=false; c.pilotTracker='unwrap';
c.fftWindowMode='peak'; c.pilotSlopeCandidates=33;
c.timingWindowPlacement='early'; c.fixedChannel=false; c.quantizedPilotRom=false;
c.channelFusion=false; c.channelFusionFixed=false; c.temporalPilots=false;
c.channelFusionPhase='quadrant';
c.llrScale=1;
switch mode
    case 'baseline'
    case 'delay'
        c.channelEstimator='delay';
    case 'delay_uncertainty'
        c.channelEstimator='delay'; c.channelErrorAwareLLR=true;
    case 'proposed'
        c.channelEstimator='delay'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular';
    case 'safe_window'
        c.channelEstimator='delay'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular'; c.fftWindowMode='energy';
    case 'compact_channel'
        c.channelEstimator='fir7'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular'; c.fftWindowMode='energy';
    case {'compact','compact_fused','compact_tracked','compact_tracked_fixed'}
        c.channelEstimator='fir7'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular'; c.fftWindowMode='energy';
        c.pilotSlopeCandidates=9;
        c.channelFusion=~strcmp(mode,'compact');
        c.temporalPilots=any(strcmp(mode,{'compact_tracked','compact_tracked_fixed'}));
        c.channelFusionFixed=strcmp(mode,'compact_tracked_fixed');
        c.fixedChannel=c.channelFusionFixed; c.quantizedPilotRom=c.fixedChannel;
    case 'compact_fir5'
        c.channelEstimator='fir5'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular'; c.fftWindowMode='energy';
        c.pilotSlopeCandidates=9;
    case {'compact_center','compact_fixed'}
        c.channelEstimator='fir7'; c.channelErrorAwareLLR=true;
        c.pilotTracker='circular'; c.fftWindowMode='energy';
        c.pilotSlopeCandidates=9; c.timingWindowPlacement='center';
        c.fixedChannel=strcmp(mode,'compact_fixed');
        c.quantizedPilotRom=c.fixedChannel;
    otherwise
        error('Unknown receiver mode: %s',mode);
end
end
