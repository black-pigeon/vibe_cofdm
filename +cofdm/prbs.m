function b = prbs(n,seed)
% PRBS x^7+x^4+1. State=bitget(seed,7:-1:1), output state(7),
% feedback=xor(state(7),state(4)), shift toward increasing indices.
assert(seed>=1 && seed<=127);
s = logical(bitget(uint8(seed),7:-1:1)).';
b = false(n,1);
for k=1:n
    b(k)=s(7); s=[xor(s(7),s(4)); s(1:6)];
end
end
