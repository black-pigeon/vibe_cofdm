function report=verify_full_link_llr(vecdir,outPath)
% Decode raw captured RTL LLRs using the scalar decoder's Q2 arithmetic.
% Complements XSim's byte/CRC checks; does not claim bit-exact frontend math.
if nargin<2,outPath=fullfile(vecdir,'llr_check.json');end
cfg=readhex(fullfile(vecdir,'rx_config.mem'));L=cfg(3);seed=cfg(4);
raw=readmatrix(fullfile(vecdir,'rtl_llr.txt'),'FileType','text');raw=raw(:);
expected=logical(readhex(fullfile(vecdir,'rx_bits.mem')));
assert(numel(raw)==cfg(2),'Incomplete RTL LLR capture: %d/%d',numel(raw),cfg(2));
assert(all(isfinite(raw)) && all(raw==fix(raw)),'Noninteger/unknown RTL LLR');
q=max(-63,min(63,raw));code=cofdm.ldpc_code();c=cofdm.config_v2();c.quantizedDecoder=true;
c.ldpcIterations=12;c.ldpcAlpha=.75;
blocks=reshape(q/4,648,[]);u=false(324,size(blocks,2));ok=false(1,size(blocks,2));its=zeros(size(ok));
for w=1:size(blocks,2),[u(:,w),ok(w),its(w)]=cofdm.ldpc_decode(blocks(:,w),code,c);end
b=xor(u(:),cofdm.prbs(numel(u),seed));used=8*L+32;
crcOk=cofdm.crc(b(1:used),32,true);paddingOk=~any(b(used+1:end));
byteOk=isequal(cofdm.bits_to_bytes(b(1:8*L)),uint8(mod((0:L-1).',256)));
report=struct('payloadBytes',L,'llrs',numel(raw),'signErrors',sum((raw<0)~=expected),...
 'zeroLLRs',sum(raw==0),'saturatedInputs',sum(abs(raw)>63),...
 'failedCodewords',find(~ok),'iterations',its,'crcOk',crcOk,'paddingOk',paddingOk,...
 'bytesOk',byteOk,'pass',all(ok)&&crcOk&&paddingOk&&byteOk,...
 'scope','MATLAB Q2 decoder on actual RTL LLR capture; INPUT_SHIFT=0');
f=fopen(outPath,'w');assert(f>=0);cl=onCleanup(@()fclose(f));fprintf(f,'%s\n',jsonencode(report));disp(report);
end
function v=readhex(p)
f=fopen(p);assert(f>=0);cl=onCleanup(@()fclose(f));v=fscanf(f,'%x');
end
