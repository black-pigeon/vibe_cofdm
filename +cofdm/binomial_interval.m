function [lo,hi,upper] = binomial_interval(errors,trials)
% Exact Clopper-Pearson 95% two-sided interval and one-sided 95% upper.
assert(isscalar(trials) && trials>=1 && trials==floor(trials));
assert(isscalar(errors) && errors>=0 && errors<=trials && errors==floor(errors));
lo=0; hi=1; upper=1;
if errors>0, lo=betaincinv(0.025,errors,trials-errors+1); end
if errors<trials
    hi=betaincinv(0.975,errors+1,trials-errors);
    upper=betaincinv(0.95,errors+1,trials-errors);
end
end
