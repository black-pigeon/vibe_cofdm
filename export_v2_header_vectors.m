function export_v2_header_vectors(outDir)
% Export descrambled v2 Header LLR vectors for the FPGA Viterbi/CRC block.
root=fileparts(mfilename('fullpath')); addpath(root);
if nargin<1, outDir=fullfile(root,'vectors','v2_header'); end
if ~exist(outDir,'dir'), mkdir(outDir); end
c=cofdm.config_v2();
payloads=[1 257 2048]; seeds=[1 93 127]; mids=[0 1 2];
fid=fopen(fullfile(outDir,'manifest.csv'),'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,'case,payload_bytes,seed,midamble,expected_ok\n');
for n=1:numel(payloads)
    cc=c; cc.scramblerSeed=seeds(n); cc.midambleCode=mids(n);
    map=cofdm.header_v2('encode',payloads(n),cc);
    % header_v2 encode returns scrambled mapped bits; undo the PHY scrambler,
    % exactly as the packetizer does before feeding this decoder.
    coded=xor(map,cofdm.prbs(numel(map),cc.headerScramblerSeed));
    llr=32767*(1-2*double(coded));
    write_vec(fullfile(outDir,sprintf('valid_%d.mem',n)),llr);
    fprintf(fid,'valid_%d,%d,%d,%d,1\n',n,payloads(n),cc.scramblerSeed,cc.midambleCode);
    if n==1
        % An all-zero soft header is a deterministic unsupported-version case;
        % it cannot be repaired into a valid v2 field set by Viterbi.
        bad=zeros(size(llr)); write_vec(fullfile(outDir,'invalid_fields.mem'),bad);
        fprintf(fid,'invalid_fields,%d,%d,%d,0\n',payloads(n),cc.scramblerSeed,cc.midambleCode);
    end
end
fprintf('Exported v2 Header vectors to %s\n',outDir);
end
function write_vec(path,llr)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
fprintf(fid,'%04x\n',mod(round(llr),65536));
end
