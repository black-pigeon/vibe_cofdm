function export_vectors(outDir)
% Golden vectors for RTL; manifest defines all signs/order/scaling.
root=fileparts(mfilename('fullpath')); addpath(root);
if nargin<1, outDir=fullfile(root,'vectors','generated'); end
if ~exist(outDir,'dir'), mkdir(outDir); end
c=cofdm.config(); code=cofdm.ldpc_code(); cofdm.seed_rng(c.seed);
payload=uint8(mod((0:c.payloadBytes-1).',256));
[wave,meta]=cofdm.tx(payload,1,c,code);
iq=[real(wave),imag(wave)]; q=round(iq*2^14);
clips=sum(q(:)>32767 | q(:)<-32768); assert(clips==0,'TX IQ saturation');
q=max(-32768,min(32767,q));
write_csv(fullfile(outDir,'tx_iq_s16_q14.csv'),q,'%d,%d\n');
write_csv(fullfile(outDir,'payload_bytes.csv'),double(payload),'%d\n');
write_csv(fullfile(outDir,'payload_codeword_bits.csv'),double(meta.codedBits),'%d\n');
write_csv(fullfile(outDir,'header_codeword_bits.csv'),double(meta.headerBits),'%d\n');
write_csv(fullfile(outDir,'ldpc_base_shifts.csv'),code.B,[repmat('%d,',1,23) '%d\n']);
write_csv(fullfile(outDir,'interleaver_zero_based.csv'),c.interleaver(:)-1,'%d\n');
t=cofdm.training(c);
write_csv(fullfile(outDir,'ltf_freq.csv'),[c.active,real(t.ltf),imag(t.ltf)],'%d,%.17g,%.17g,%.17g,%.17g\n');
fid=fopen(fullfile(outDir,'manifest.txt'),'w'); assert(fid>=0);
cl=onCleanup(@()fclose(fid));
fprintf(fid,'COFDM v0.1 profile=1 seq=1 seed=%d\n',c.seed);
fprintf(fid,'TX columns I,Q; signed decimal 16-bit; value=integer/16384. No CSV headers.\n');
fprintf(fid,'TX samples=%d (includes %d zero guard); IFFT=sqrt(256)*ifft; TX scale=0.25.\n',numel(wave),c.guardSamples);
fprintf(fid,'Bits: bytes MSB-first, codewords sequential/systematic then parity, QPSK I bit then Q bit, 0=>positive.\n');
fprintf(fid,'QC H: row i column mod(i+shift,27), zero-based; -1 absent.\n');
fprintf(fid,'Interleaver: transmitted bit i = source bit mod(13*i,384), zero-based.\n');
fprintf(fid,'LTF CSV columns signed_k,Re_LTF1,Re_LTF2,Im_LTF1,Im_LTF2.\n');
fprintf(fid,'PAPR_sample_db=%.8f clipped_components=%d\n',meta.paprDb,clips);
fprintf('Exported vectors to %s\n',outDir);
end
function write_csv(path,x,fmt)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,fmt,x.');
end
