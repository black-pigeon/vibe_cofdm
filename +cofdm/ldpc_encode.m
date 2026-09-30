function cw = ldpc_encode(u,code)
% QC XOR encoder for the specific 648,324 rate-1/2 parity structure.
% No dense inverse: first parity block is XOR of all information syndromes.
u=logical(u(:)); assert(numel(u)==code.k);
s=logical(mod(code.H(:,1:code.k)*double(u),2));
s=reshape(s,code.z,[]);
p=false(code.z,12);
p(:,1)=mod(sum(s,2),2)~=0;
p(:,2)=xor(s(:,1),circshift(p(:,1),-1));
for r=2:11
    p(:,r+1)=xor(s(:,r),p(:,r));
    if r==7, p(:,r+1)=xor(p(:,r+1),p(:,1)); end
end
cw=[u;p(:)];
assert(~any(mod(code.H*double(cw),2)),'Encoder syndrome failure');
end
