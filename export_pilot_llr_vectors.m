function export_pilot_llr_vectors(outDir)
%EXPORT_PILOT_LLR_VECTORS Golden vectors for the pre-LDPC soft demapper.
% Inputs are the signed integers exchanged with RTL.  The reference uses
% exactly the same multiply/accumulate and arithmetic-right-shift rules as
% cofdm_matched_llr, so a mismatch cannot be hidden by a later LDPC decode.
if nargin < 1
    root = fileparts(mfilename('fullpath'));
    outDir = fullfile(root,'vectors','pilot_llr');
end
if ~exist(outDir,'dir'), mkdir(outDir); end
rng(20260929,'twister');
n = 96;
y_re = randi([-28000 28000],n,1);
y_im = randi([-28000 28000],n,1);
h_re = randi([-90000 90000],n,1);
h_im = randi([-90000 90000],n,1);
inv_noise = randi([256 2^20],n,1);
mode_bpsk = zeros(n,1); mode_bpsk(1:2:end)=1;

% cofdm_matched_llr defaults: YW=16, HW=18, INV_W=24,
% LLR_SHIFT=29+16-8=37.  All operations are integer and signed.
prod_rr = int64(y_re).*int64(h_re);
prod_ii = int64(y_im).*int64(h_im);
prod_ir = int64(y_im).*int64(h_re);
prod_ri = int64(y_re).*int64(h_im);
m_re = prod_rr + prod_ii;
m_im = prod_ir - prod_ri;
scaled_re = m_re.*int64(inv_noise);
scaled_im = m_im.*int64(inv_noise);
% Use integer division: converting the 59-bit product to double before
% floor() can move a value exactly below a power-of-two boundary by one.
q_re = idivide(scaled_re,int64(2^37),'floor');
q_im = idivide(scaled_im,int64(2^37),'floor');
llr_re = sat16(q_re); llr_im = sat16(q_im);
llr_im(mode_bpsk~=0)=0; % BPSK consumes only the real component.
sat = (q_re > 32767) | (q_re < -32768) | ...
      (q_im > 32767) | (q_im < -32768);

write_hex(fullfile(outDir,'y_re.hex'),y_re,16);
write_hex(fullfile(outDir,'y_im.hex'),y_im,16);
write_hex(fullfile(outDir,'h_re.hex'),h_re,18);
write_hex(fullfile(outDir,'h_im.hex'),h_im,18);
write_hex(fullfile(outDir,'inv_noise.hex'),inv_noise,24);
write_hex(fullfile(outDir,'mode_bpsk.hex'),mode_bpsk,1);
write_hex(fullfile(outDir,'expected_re.hex'),llr_re,16);
write_hex(fullfile(outDir,'expected_im.hex'),llr_im,16);
write_hex(fullfile(outDir,'expected_sat.hex'),sat,1);
fid=fopen(fullfile(outDir,'expected.txt'),'w'); assert(fid>=0);
fprintf(fid,'COUNT=%d LLR_SHIFT=37 YW=16 HW=18 INV_W=24\n',n);
fprintf(fid,'matched=conj(H)*Y; arithmetic right shift and signed saturation\n');
fclose(fid);
fprintf('Exported pilot/LLR RTL vectors to %s\n',outDir);
end

function y=sat16(x)
y=max(-32768,min(32767,x));
end

function write_hex(path,x,b)
fid=fopen(path,'w'); assert(fid>=0); c=onCleanup(@()fclose(fid));
modv=2^b; nd=ceil(b/4);
for k=1:numel(x)
    fprintf(fid,'%0*X\n',nd,mod(double(x(k)),modv));
end
end
