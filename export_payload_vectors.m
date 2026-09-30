function export_payload_vectors()
% Independent existing MATLAB LDPC quantized model and CRC/PRBS golden data.
root=fileparts(mfilename('fullpath'));addpath(root);
out=fullfile(root,'vectors','qcldpc');if ~exist(out,'dir'),mkdir(out);end
code=cofdm.ldpc_code(); c=cofdm.config_v2();c.quantizedDecoder=true;
rng(725,'twister');
for t=0:7
    u=rand(324,1)>.5;if t==0,u(:)=false;end
    cw=cofdm.ldpc_encode(u,code);
    if t<4
        llr=24*(1-2*double(cw));
        ix=randperm(648,1+5*t);llr(ix)=-4*(1-2*double(cw(ix)));
    elseif t==4
        llr=round(10*(1-2*double(cw))+10*randn(648,1));
    elseif t==5
        llr=round(8*randn(648,1)); % nonconvergent / iteration-limit case
    elseif t==6
        llr=63*(1-2*double(cw)); % saturation/ties
    else
        llr=zeros(648,1); % deterministic zero/tie behavior
    end
    llr=max(-63,min(63,llr));
    [bits,ok,it,post]=cofdm.ldpc_decode(llr/4,code,c);
    if t<4,assert(ok && isequal(bits,u));end
    wr(fullfile(out,sprintf('llr%d.mem',t)),mod(llr,128),2);
    wr(fullfile(out,sprintf('bits%d.mem',t)),bits,1);
    wr(fullfile(out,sprintf('meta%d.mem',t)),[ok;it],2);
    wr(fullfile(out,sprintf('post%d.mem',t)),mod(round(post*4),512),3);
    fprintf('LDPC case %d ok=%d iterations=%d\n',t,ok,it);
end
lens=[1 36 37 257 2048 257 37];
for t=0:numel(lens)-1
    len=lens(t+1);seed=mod(t*23,127)+1;cfg=cofdm.frame_layout(c,len);
    payload=uint8(randi([0 255],len,1));
    b=cofdm.crc(cofdm.bytes_to_bits(payload),32);
    if t==5,b(8*len+1)=~b(8*len+1);end % valid LDPC, bad PHY CRC
    b=[b;false(cfg.infoPadBits,1)];
    if t==6,b(end)=true;end % good CRC, nonzero information padding
    b=xor(b,cofdm.prbs(numel(b),seed));
    cw=false(648,cfg.nCodewords);
    for j=1:cfg.nCodewords,cw(:,j)=cofdm.ldpc_encode(b((j-1)*324+(1:324)),code);end
    wr(fullfile(out,sprintf('frame%d_llr.mem',t)),mod(24*(1-2*double(cw(:))),128),2);
    wr(fullfile(out,sprintf('frame%d_bits.mem',t)),b,1);
    wr(fullfile(out,sprintf('frame%d_bytes.mem',t)),payload,2);
    wr(fullfile(out,sprintf('frame%d_meta.mem',t)),[len;seed;cfg.nCodewords;t<5],8);
end
end
function wr(p,v,n)
f=fopen(p,'w');assert(f>=0);cl=onCleanup(@()fclose(f));fprintf(f,['%0' num2str(n) 'x\n'],double(v));
end
