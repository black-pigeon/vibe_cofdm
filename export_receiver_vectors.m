function export_receiver_vectors(outDir)
% Standalone integer FIR and pilot-ROM fixtures, not full RX fixed vectors.
root=fileparts(mfilename('fullpath')); addpath(root);
if nargin<1, outDir=fullfile(root,'vectors','receiver_fixed'); end
if ~exist(outDir,'dir'), mkdir(outDir); end
c=cofdm.receiver_config(cofdm.config(),'compact_fixed');
cofdm.seed_rng(20261006);
raw=0.25*exp(-1j*2*pi/c.nfft*(c.active*[2 13 27]))*[1;0.25j;-0.12];
raw=raw+0.02*(randn(size(raw))+1j*randn(size(raw)));
raw=cofdm.quantize_signed(raw,c.channelWordBits,c.channelFractionBits);
[H,~,d]=cofdm.estimate_channel(raw,0.0008,c); assert(d.saturations==0);
scale=2^c.channelFractionBits; coefScale=2^c.coefficientFractionBits;
writecsv(fullfile(outDir,'fir_input.csv'),'signed_carrier,i_s18_f14,q_s18_f14', ...
    [c.active,round(real(raw)*scale),round(imag(raw)*scale)]);
writecsv(fullfile(outDir,'fir_expected.csv'),'signed_carrier,i_s18_f14,q_s18_f14', ...
    [c.active,round(real(H)*scale),round(imag(H)*scale)]);
phase=(0:15).'; rotation=cofdm.quantize_signed(exp(1j*2*pi*phase/16),18,16);
writecsv(fullfile(outDir,'rotation_rom.csv'),'phase_mod16,i_s18_f16,q_s18_f16', ...
    [phase,round(real(rotation)*coefScale),round(imag(rotation)*coefScale)]);
grid=(-100:100).'; valid=double(grid~=0); kernel=[1;6;15;20;15;6;1];
weights=conv(valid,kernel,'same'); reciprocal=cofdm.quantize_signed(1./weights,18,16);
writecsv(fullfile(outDir,'normalization_rom.csv'),'signed_carrier,valid,weight,reciprocal_s18_f16', ...
    [grid,valid,weights,round(reciprocal*coefScale)]);
slopes=linspace(-c.phaseSlopeMax,c.phaseSlopeMax,c.pilotSlopeCandidates);
rom=cofdm.quantize_signed(exp(-1j*c.pilots*slopes),18,16);
[pilot,candidate]=ndgrid(c.pilots,0:c.pilotSlopeCandidates-1);
writecsv(fullfile(outDir,'pilot_rom.csv'),'pilot_carrier,candidate_zero_based,i_s18_f16,q_s18_f16', ...
    [pilot(:),candidate(:),round(real(rom(:))*coefScale),round(imag(rom(:))*coefScale)]);
manifest=struct('receiver','compact_fixed','seed',20261006, ...
    'dataBits',18,'dataFractionBits',14,'coefficientBits',18,'coefficientFractionBits',16, ...
    'accumulatorBits',26,'accumulatorFractionBits',14,'kernel',kernel.', ...
    'rounding','nearest; half ties away from zero; saturate after rounding', ...
    'arithmetic','full complex product before narrowing; no per-real-product truncation', ...
    'stageOrder',{{'input','preRotate','FIR_accumulate','normalize','postRotate'}}, ...
    'missingCarrier','DC and outside [-100,100] have zero weight; retain grid spacing', ...
    'rotationAddress','mod(signed_carrier,16); conjugate for postRotate', ...
    'pilotSlopes',slopes,'noiseVarianceFloat',0.0008,'saturations',d.saturations);
fid=fopen(fullfile(outDir,'manifest.json'),'w'); assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s\n',jsonencode(manifest));
fprintf('Exported fixed FIR input/output and coefficient ROM to %s\n',outDir);
end
function writecsv(path,header,values)
fid=fopen(path,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',header);
format=[repmat('%d,',1,size(values,2)-1) '%d\n']; fprintf(fid,format,values.');
end
