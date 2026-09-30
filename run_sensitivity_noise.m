function results = run_sensitivity_noise(nWindows,outPath)
% Noise-only captured windows: stage false accepts, NOT continuous-stream FAR.
if nargin<1, nWindows=1000; end
if nargin<2, outPath=''; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config_v2('compact'); code=cofdm.ldpc_code(); cofdm.seed_rng(202609284);
samples=32320; counts=zeros(1,4);
for k=1:nWindows
    y=(randn(samples,1)+1j*randn(samples,1))/sqrt(2);
    r=cofdm.rx(y,c,code);
    counts(1)=counts(1)+~strcmp(r.sync.reason,'STF not found');
    counts(2)=counts(2)+r.sync.ok;
    if isfield(r,'header'), counts(3)=counts(3)+r.header.ok; end
    counts(4)=counts(4)+r.ok;
end
upper=zeros(size(counts));
for k=1:4, [~,~,upper(k)]=cofdm.binomial_interval(counts(k),nWindows); end
results=table(nWindows,samples,samples/c.fs,counts(1),counts(2),counts(3),counts(4), ...
    upper(1),upper(2),upper(3),upper(4),'VariableNames', ...
    {'windows','samples_per_window','window_seconds','stf_candidates','sync_accepts', ...
    'header_accepts','payload_accepts','stf_upper95','sync_upper95','header_upper95','payload_upper95'});
disp(results);
if ~isempty(outPath)
    writetable(results,outPath);
    metadata=struct('complete',true,'seed',202609284,'config',c, ...
        'model','independent circular complex unit-variance AWGN windows', ...
        'matlabVersion',version,'windows',nWindows,'samplesPerWindow',samples);
    fid=fopen([outPath '.json'],'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(metadata));
end
end
