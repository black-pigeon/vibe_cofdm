function b = link_budget(p)
% LINK_BUDGET Illustrative free-space budget; NOT a measured range claim.
% paRatedDbm is the chosen PA reference power; backoff gives average OFDM power.
% requiredSnrDb must ultimately come from full-link PER characterization.
if nargin<1
    p=struct('carrierHz',2.4e9,'noiseBandwidthHz',12e6, ...
        'paRatedDbm',30,'backoffDb',6,'txGainDbi',6,'rxGainDbi',6, ...
        'txLossDb',1,'rxLossDb',1,'noiseFigureDb',5, ...
        'requiredSnrDb',6,'implementationLossDb',3,'fadeMarginDb',15);
end
assert(p.carrierHz>0 && p.noiseBandwidthHz>0 && p.backoffDb>=0);
b.assumptions=p;
b.noiseDbm=-174+10*log10(p.noiseBandwidthHz)+p.noiseFigureDb;
b.sensitivityDbm=b.noiseDbm+p.requiredSnrDb+p.implementationLossDb;
b.averageTxDbm=p.paRatedDbm-p.backoffDb;
b.eirpDbm=b.averageTxDbm+p.txGainDbi-p.txLossDb;
b.pathLossBudgetDb=b.eirpDbm+p.rxGainDbi-p.rxLossDb- ...
    b.sensitivityDbm-p.fadeMarginDb;
b.freeSpaceKm=10^((b.pathLossBudgetDb-32.45-20*log10(p.carrierHz/1e6))/20);
fprintf('ASSUMPTIONS ONLY: avg TX %.2f dBm, EIRP %.2f dBm, sensitivity %.2f dBm\n', ...
    b.averageTxDbm,b.eirpDbm,b.sensitivityDbm);
fprintf('Path loss budget %.2f dB; free-space equivalent %.3f km (not coverage)\n', ...
    b.pathLossBudgetDb,b.freeSpaceKm);
end
