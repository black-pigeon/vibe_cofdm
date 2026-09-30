function seed_rng(seed)
% Repeatable within the selected engine; MATLAB/Octave streams may differ.
if exist('rng','file') || exist('rng','builtin')
    rng(seed,'twister');
else
    rand('state',seed); randn('state',seed); %#ok<RAND>
end
end
