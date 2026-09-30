function rows = run_fixed_precision(outPath)
% Paired module-only word-length sweep, distinct from end-to-end PER.
if nargin<1, outPath=''; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.receiver_config(cofdm.config(),'compact_center');
cofdm.seed_rng(20261003);
formats=[12 8 12 10 20;16 12 16 14 24;18 14 18 16 26];
amplitudes=[0.001 0.01 0.25 2]; rows=zeros(0,9);
for amplitude=amplitudes
    error=zeros(3,1); energy=0; sat=zeros(3,1);
    for trial=1:100
        h=amplitude*exp(-1j*2*pi/c.nfft*(c.active*[2 13 27])) ...
            *[1;0.25*exp(2j*pi*rand);0.12*exp(2j*pi*rand)];
        raw=h+amplitude*0.2/sqrt(2)*(randn(size(h))+1j*randn(size(h)));
        reference=cofdm.estimate_channel(raw,amplitude^2*0.04,c);
        energy=energy+sum(abs(reference).^2);
        for k=1:3
            q=c; q.fixedChannel=true;
            q.channelWordBits=formats(k,1); q.channelFractionBits=formats(k,2);
            q.coefficientWordBits=formats(k,3); q.coefficientFractionBits=formats(k,4);
            q.channelAccumulatorBits=formats(k,5);
            [estimate,~,d]=cofdm.estimate_channel(raw,amplitude^2*0.04,q);
            error(k)=error(k)+sum(abs(estimate-reference).^2);
            sat(k)=sat(k)+d.saturations;
        end
    end
    for k=1:3
        nmse=10*log10(error(k)/energy);
        rows(end+1,:)=[amplitude formats(k,:) 100 nmse sat(k)]; %#ok<AGROW>
        fprintf('FIR input scale %g bits %d frac %d NMSE %.2f dB saturation %d\n', ...
            amplitude,formats(k,1),formats(k,2),nmse,sat(k));
    end
end
if ~isempty(outPath)
    fid=fopen(outPath,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'input_scale,word_bits,fraction_bits,coefficient_bits,coefficient_fraction_bits,accumulator_bits,trials,error_vs_float_nmse_db,saturations\n');
    fprintf(fid,'%.8g,%d,%d,%d,%d,%d,%d,%.8g,%d\n',rows.');
end
end
