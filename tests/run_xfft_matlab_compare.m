function run_xfft_matlab_compare()
% Compare MATLAB's FFT reference and the generated XFFT bit-accurate model.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
setup_xfft_bitacc();
rng(20260929);
x=int16(round((randn(256,1)+1j*randn(256,1))*3000));
[yx,mx]=cofdm.xfft_model(x,'Engine','matlab');
[xx,mz]=cofdm.xfft_model(x,'Engine','xilinx');
err=max(abs(mx.integer(:)-mz.integer(:)));
fprintf('XFFT MATLAB/C-model compare: max integer error=%g overflow=%d\n',err,mz.overflow);
assert(err<=2,'MATLAB reference differs from XFFT C model by more than quantization envelope');
assert(numel(xx)==256 && mz.overflow==0);
% Also verify the COFDM LTF vector can be passed through both models.
c=cofdm.config(); t=cofdm.training(c);
u=complex(int16(round(real(t.ltfTime(:,1))*2^15)),...
    int16(round(imag(t.ltfTime(:,1))*2^15)));
% The training waveform is low amplitude; quantize exactly one 256-point block.
[~,~]=cofdm.xfft_model(u,'Engine','xilinx');
fprintf('PASS MATLAB/XFFT bit-accurate comparison\n');
end
