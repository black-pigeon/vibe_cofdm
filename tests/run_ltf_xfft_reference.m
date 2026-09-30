function run_ltf_xfft_reference()
% Exercise the MATLAB and Xilinx-model LTF/fine-CFO reference paths.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); addpath(fullfile(root,'tools'));
c=cofdm.config(); t=cofdm.training(c); f0=12500; n=(0:2*(c.nfft+c.ncp)-1).';
s1=cofdm.ofdm_symbol(c,t.ltf(:,1)); s2=cofdm.ofdm_symbol(c,t.ltf(:,2));
v=[s1;s2].*exp(1j*2*pi*f0*n/c.fs);
a=c.ncp+1;
rm=cofdm.ltf_process(v,a,c,'Engine','matlab');
setup_xfft_bitacc();
rx=cofdm.ltf_process(v,a,c,'Engine','xilinx');
fprintf('LTF MATLAB CFO=%g Hz, XFFT-model CFO=%g Hz, expected=%g Hz\n',...
    rm.fineCfoHz,rx.fineCfoHz,f0);
assert(abs(rm.fineCfoHz-f0)<100 && abs(rx.fineCfoHz-f0)<500);
assert(abs(rm.fineCfoHz-rx.fineCfoHz)<500);
fprintf('PASS MATLAB/XFFT LTF and fine-CFO reference\n');
end
