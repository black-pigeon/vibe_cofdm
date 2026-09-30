function export_pre_ldpc_stream_vectors(outDir)
% Independent MATLAB oracles for natural-bin reorder, header PRBS and mapping.
root=fileparts(mfilename('fullpath')); addpath(root);
if nargin<1, outDir=fullfile(root,'vectors','pre_ldpc_stream'); end
if ~exist(outDir,'dir'), mkdir(outDir); end
c=cofdm.config(); cofdm.seed_rng(20260929);
writehex(fullfile(outDir,'pilot_bits.mem'),double(cofdm.prbs(8*40,53)),1);
writehex(fullfile(outDir,'header_bits.mem'),double(cofdm.prbs(768,31)),1);
bins=sort(c.dataBins)-1;
[~,order]=ismember(bins+1,c.dataBins);
% Four BPSK headers (legacy v1) and four data symbols; two LDPC words.
inputs=[]; outputs=[]; flags=[];
for sym=1:8
    pair=randi([-32768 32767],192,2);
    if sym==1, pair(1,1)=-32768; end
    inputs=[inputs;pair]; %#ok<AGROW>
    carrier=zeros(192,2); carrier(order,:)=pair;
    if sym<=4
        bits=cofdm.prbs(768,31);
        z=carrier(:,1).*(1-2*double(bits((sym-1)*192+(1:192))));
        z=max(-32768,min(32767,z));
        f=ones(192,1); f(end)=3; % header bit0, symbol_last bit1
    else
        serial=reshape(carrier.',[],1); z=zeros(384,1);
        z(c.interleaver)=serial;
        offset=(sym-5)*384; n=min(384,1296-offset); z=z(1:n);
        k=(offset:offset+n-1).';
        f=4*(mod(k,648)==0)+8*(mod(k,648)==647); f(end)=f(end)+2;
    end
    outputs=[outputs;z]; flags=[flags;f]; %#ok<AGROW>
end
writehex(fullfile(outDir,'bins.mem'),bins,2);
writehex(fullfile(outDir,'pairs.mem'),mod(inputs(:,1),65536)+65536*mod(inputs(:,2),65536),8);
writehex(fullfile(outDir,'expected.mem'),mod(outputs,65536),4);
writehex(fullfile(outDir,'flags.mem'),flags,1);
% Integrated v2 test: real transmitter symbols, a skipped midamble and
% 7 codewords spanning 12 QPSK symbols. Known +pi/2 common phase.
v2=cofdm.config_v2(); code=cofdm.ldpc_code();
[wave,meta]=cofdm.tx(uint8(mod((0:256).',256)),0,v2,code);
cc=meta.config; t=cofdm.training(cc);
pos=numel(t.stf)+2*(cc.nfft+cc.ncp)+cc.ncp+1;
fftPairs=[]; kinds=[];
for k=3:numel(meta.symbolTypes)
    Y=fft(wave(pos:pos+255))/sqrt(256)*1j;
    fftPairs=[fftPairs;round([real(Y) imag(Y)]*32768)]; %#ok<AGROW>
    kinds=[kinds;strcmp(meta.symbolTypes{k},'HEADER')+2*strcmp(meta.symbolTypes{k},'MIDAMBLE')]; %#ok<AGROW>
    pos=pos+288;
end
hmap=cofdm.header_v2('encode',257,cc);
header=xor(hmap,cofdm.prbs(192,31));
writehex(fullfile(outDir,'stream_fft.mem'),mod(fftPairs(:,1),65536)+65536*mod(fftPairs(:,2),65536),8);
writehex(fullfile(outDir,'stream_kind.mem'),kinds,1);
writehex(fullfile(outDir,'stream_bits.mem'),double([header;meta.codedBits]),1);
assert(numel(kinds)==14 && cc.nCodewords==7);
fprintf('Exported %d pairs -> %d LLRs, including saturation and coded padding\n',size(inputs,1),numel(outputs));
end
function writehex(path,values,width)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,['%0' num2str(width) 'x\n'],values);
end
