function r=ltf_process(v,ltfUsefulStart,c,varargin)
%LTF_PROCESS Golden reference for the two-LTF FPGA processing stage.
% v is already coarse-CFO corrected. ltfUsefulStart is the 1-based start of
% LTF1 useful samples (the CP has already been skipped). The function can
% use MATLAB FFT or the Xilinx bit-accurate C model through xfft_model.
p=inputParser; addParameter(p,'Engine','matlab'); addParameter(p,'InputWidth',16);
parse(p,varargin{:}); p=p.Results;
span=c.nfft+c.ncp; a=ltfUsefulStart; b=a+span;
assert(a>=1 && b+c.nfft-1<=numel(v),'LTF samples are outside the capture');
t=cofdm.training(c);
Y1=one_fft(v(a:a+c.nfft-1),c,p.Engine,p.InputWidth);
Y2=one_fft(v(b:b+c.nfft-1),c,p.Engine,p.InputWidth);
Y1a=Y1(c.activeBins); Y2a=Y2(c.activeBins);
H1=Y1a./t.ltf(:,1); H2=Y2a./t.ltf(:,2);
phase=angle(sum(H2.*conj(H1)));
r=struct('engine',p.Engine,'Y1',Y1,'Y2',Y2,'H1',H1,'H2',H2,...
    'finePhaseRad',phase,'fineCfoHz',phase*c.fs/(2*pi*span),...
    'finePhaseInc',round(-phase*c.fs/(2*pi*span)/c.fs*2^32));
r.channel=(H1+H2)/2;
end

function Y=one_fft(x,c,engine,w)
switch lower(engine)
    case 'matlab'
        Y=fft(x)/sqrt(c.nfft);
    case {'xilinx','xfft'}
        q=2^(w-1);
        xq=complex(int16(max(min(round(real(x)*q),q-1),-q)),...
                   int16(max(min(round(imag(x)*q),q-1),-q)));
        [z,meta]=cofdm.xfft_model(xq,'Engine','xilinx','InputWidth',w);
        % The XFFT output is FFT(x)/2^sum(scale). Convert to the MATLAB
        % project convention FFT(x)/sqrt(N) before forming H and CFO.
        Y=z*(2^sum(meta.scaling))/sqrt(c.nfft);
    otherwise
        error('ltf_process:engine','Engine must be matlab or xilinx');
end
end
