function [y, meta] = xfft_model(x, varargin)
%XFFT_MODEL Compare MATLAB FFT with the Vivado XFFT bit-accurate model.
%
% The XFFT C model uses normalized fixed-point samples in [-1,1).  This
% wrapper accepts the same signed integer samples used by the RTL (Q1.(W-1))
% and returns both normalized complex values and quantized integer values.
% Engine='matlab' is a transparent algorithmic reference; Engine='xilinx'
% calls xfft_v9_1_bitacc_mex after setup_xfft_bitacc has built the MEX file.

p=inputParser;
addParameter(p,'Engine','matlab');
addParameter(p,'NFFT',256);
addParameter(p,'InputWidth',16);
addParameter(p,'TwiddleWidth',16);
addParameter(p,'Scaling',[3 2 2 2]);
addParameter(p,'Direction',1);
addParameter(p,'Quantize',true);
parse(p,varargin{:}); p=p.Results;
x=x(:); assert(numel(x)==p.NFFT,'XFFT input must contain NFFT samples');
assert(all(abs(real(x))<2^(p.InputWidth-1)) && all(abs(imag(x))<2^(p.InputWidth-1)),...
    'integer input exceeds the signed input range');
qscale=2^(p.InputWidth-1);
meta=struct('engine',lower(p.Engine),'nfft',p.NFFT,'inputWidth',p.InputWidth,...
    'twiddleWidth',p.TwiddleWidth,'scaling',p.Scaling,'direction',p.Direction,...
    'overflow',0,'blockExponent',0,'bitExact',false);

switch lower(p.Engine)
    case 'matlab'
        z=double(x)/qscale;
        if p.Direction==1, z=fft(z); else, z=ifft(z)*p.NFFT; end
        y=z/(2^sum(p.Scaling));
        if p.Quantize
            yi=sat_round(y*qscale,p.InputWidth);
            y=yi/qscale;
        else
            yi=[];
        end
        meta.integer=yi; meta.bitExact=false;
    case {'xilinx','xfft'}
        if exist('xfft_v9_1_bitacc_mex','file')~=3
            error('cofdm:xfft_model:notBuilt',...
                'XFFT MEX is not built. Run matlab/tools/setup_xfft_bitacc.m first.');
        end
        g=struct('C_NFFT_MAX',log2(p.NFFT),'C_ARCH',3,'C_HAS_NFFT',0,...
            'C_USE_FLT_PT',0,'C_INPUT_WIDTH',p.InputWidth,...
            'C_TWIDDLE_WIDTH',p.TwiddleWidth,'C_HAS_SCALING',1,...
            'C_HAS_BFP',0,'C_HAS_ROUNDING',1);
        zin=complex(double(real(x))/qscale,double(imag(x))/qscale);
        [z,meta.blockExponent,meta.overflow]=xfft_v9_1_bitacc_mex(...
            g,log2(p.NFFT),zin,double(p.Scaling),p.Direction);
        y=z(:); yi=sat_round(y*qscale,p.InputWidth);
        meta.integer=yi; meta.bitExact=true;
    otherwise
        error('cofdm:xfft_model:engine','Engine must be matlab or xilinx');
end
end

function y=sat_round(x,w)
% MATLAB round is adequate for the comparison envelope; exact XFFT output
% is obtained through the Xilinx C model when convergent ties matter.
y=round(real(x))+1j*round(imag(x));
lo=-2^(w-1); hi=2^(w-1)-1;
y=complex(min(max(real(y),lo),hi),min(max(imag(y),lo),hi));
end
