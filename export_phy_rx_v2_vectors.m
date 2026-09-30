function export_phy_rx_v2_vectors(payloadBytes,cfoHz,midCode,options)
% Actual MATLAB transmitter waveform, not synthetic LLR/header injection.
if nargin<1,payloadBytes=257;end
if nargin<2,cfoHz=25000;end
if nargin<3,midCode=1;end
if nargin<4,options=struct();end
if ~isfield(options,'snrDb'),options.snrDb=Inf;end
if ~isfield(options,'seed'),options.seed=20261001;end
if ~isfield(options,'delays'),options.delays=0;end
if ~isfield(options,'gains'),options.gains=1;end
root=fileparts(mfilename('fullpath'));addpath(root);
out=fullfile(root,'vectors','phy_rx_v2');
if isfield(options,'outDir'),out=options.outDir;end
if ~exist(out,'dir'),mkdir(out);end
c=cofdm.config_v2();c.midambleCode=midCode;code=cofdm.ldpc_code();
[w,m]=cofdm.tx(uint8(mod((0:payloadBytes-1).',256)),0,c,code);
cofdm.seed_rng(options.seed);
p=struct('snrDb',options.snrDb,'cfoHz',cfoHz,'offset',64,...
    'delays',options.delays,'gains',options.gains);
[w,truth]=cofdm.channel(w,c,p);
r=cofdm.rx(w,c,code);
w=[w;zeros(8192,1)];
x=round(w*32768);assert(max(abs([real(x);imag(x)]))<32768);
wr(fullfile(out,'rx_iq.mem'),mod(real(x),65536)+65536*mod(imag(x),65536),8);
wr(fullfile(out,'rx_bits.mem'),double(m.codedBits),1);
wr(fullfile(out,'rx_config.mem'),[numel(x);numel(m.codedBits);payloadBytes;c.scramblerSeed;midCode],8);
manifest=struct('options',options,'payloadBytes',payloadBytes,'cfoHz',cfoHz,...
    'midCode',midCode,'matlabOk',r.ok,'matlabReason',r.reason,'noiseVariance',truth.noiseVariance);
f=fopen(fullfile(out,'manifest.json'),'w');assert(f>=0);fprintf(f,'%s\n',jsonencode(manifest));fclose(f);
fprintf('Export actual v2 IQ: %d samples, %d bytes, CFO %g Hz, %d LDPC bits\n',numel(x),payloadBytes,cfoHz,numel(m.codedBits));
end
function wr(p,v,n)
f=fopen(p,'w');assert(f>=0);cl=onCleanup(@()fclose(f));fprintf(f,['%0' num2str(n) 'x\n'],v);
end
