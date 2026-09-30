function [H,errorVariance,diagnostics] = estimate_channel(raw,observationVariance,c)
% Denoise unit-amplitude training LS observations; no channel truth used.
% Delay-mode uncertainty is a plug-in Bayesian approximation; FIR reports
% noise propagation only. Neither is a measured total channel-error MSE.
nv=max(observationVariance,1e-12);
diagnostics=struct('saturations',0);
if c.fixedChannel
    [H,errorVariance,diagnostics]=cofdm.fir_channel_fixed(raw,nv,c); return;
end
if strcmp(c.channelEstimator,'ls')
    H=raw; errorVariance=nv*ones(size(raw)); return;
end
if any(strcmp(c.channelEstimator,{'fir5','fir7'}))
    % Center the CP delay interval before local smoothing. Integer k spacing
    % is retained across DC; missing DC/guard observations carry zero weight.
    rotation=exp(1j*2*pi*c.active*c.smoothingCenterDelay/c.nfft);
    grid=(min(c.active):max(c.active)).'; idx=c.active-min(c.active)+1;
    samples=zeros(size(grid)); valid=zeros(size(grid));
    samples(idx)=raw.*rotation; valid(idx)=1;
    kernel=[1;4;6;4;1]; % denominator cancels in masked convolution
    if strcmp(c.channelEstimator,'fir7'), kernel=[1;6;15;20;15;6;1]; end
    weight=conv(valid,kernel,'same');
    smooth=conv(samples,kernel,'same')./max(weight,1);
    H=smooth(idx).*conj(rotation);
    variance=nv*conv(valid,kernel.^2,'same')./max(weight.^2,1);
    % Noise propagation only: smoothing bias / ICI are not included.
    errorVariance=variance(idx); return;
end
assert(strcmp(c.channelEstimator,'delay'));
% Eigendecomposition depends only on public carrier/support configuration.
% Production hardware must replace this floating reference with a verified
% ROM basis / low-rank projection, not compute a matrix inverse on each frame.
persistent savedActive savedDelay savedN basis eigenvalue
if isempty(basis) || ~isequal(savedActive,c.active) || ...
        ~isequal(savedDelay,c.delaySupport) || ~isequal(savedN,c.nfft)
    F=exp(-1j*2*pi/c.nfft*(c.active*c.delaySupport.'));
    [U,S,~]=svd(F,'econ');
    basis=U; eigenvalue=diag(S).^2;
    savedActive=c.active; savedDelay=c.delaySupport; savedN=c.nfft;
end
% Uniform power-delay prior across the specified support. Estimate total
% gain after subtracting known training observation noise. DC/guard bins
% are missing observations, never zero-valued channel measurements.
power=max(mean(abs(raw).^2)-nv,1e-12);
lambda=nv*numel(c.delaySupport)/power;
gain=eigenvalue./(eigenvalue+lambda);
H=basis*(gain.*(basis'*raw));
errorVariance=nv*(abs(basis).^2*gain);
errorVariance=max(real(errorVariance),0);
end
