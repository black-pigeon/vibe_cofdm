function code = ldpc_code()
% IEEE 802.11-style QC matrix, n=648, rate=1/2, Z=27.
% Matrix provenance/license: ../THIRD_PARTY_NOTICES.md. No Wi-Fi PHY claim.
% Shift convention H block row i has its 1 at column mod(i+s,Z).
B=[
    0 -1 -1 -1 0 0 -1 -1 0 -1 -1 0 1 0 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1;
    22 0 -1 -1 17 -1 0 0 12 -1 -1 -1 -1 0 0 -1 -1 -1 -1 -1 -1 -1 -1 -1;
    6 -1 0 -1 10 -1 -1 -1 24 -1 0 -1 -1 -1 0 0 -1 -1 -1 -1 -1 -1 -1 -1;
    2 -1 -1 0 20 -1 -1 -1 25 0 -1 -1 -1 -1 -1 0 0 -1 -1 -1 -1 -1 -1 -1;
    23 -1 -1 -1 3 -1 -1 -1 0 -1 9 11 -1 -1 -1 -1 0 0 -1 -1 -1 -1 -1 -1;
    24 -1 23 1 17 -1 3 -1 10 -1 -1 -1 -1 -1 -1 -1 -1 0 0 -1 -1 -1 -1 -1;
    25 -1 -1 -1 8 -1 -1 -1 7 18 -1 -1 0 -1 -1 -1 -1 -1 0 0 -1 -1 -1 -1;
    13 24 -1 -1 0 -1 8 -1 6 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 0 -1 -1 -1;
    7 20 -1 16 22 10 -1 -1 23 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 0 -1 -1;
    11 -1 -1 -1 19 -1 -1 -1 13 -1 3 17 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 0 -1;
    25 -1 8 -1 23 18 -1 14 9 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 0;
    3 -1 -1 -1 16 -1 -1 2 25 5 -1 -1 1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0];
z=27; n=24*z; m=12*z;
ri=[]; ci=[];
for r=1:12
    for c=1:24
        if B(r,c)<0, continue; end
        ri=[ri;(r-1)*z+(1:z).']; %#ok<AGROW>
        ci=[ci;(c-1)*z+mod((0:z-1).'+B(r,c),z)+1]; %#ok<AGROW>
    end
end
code.B=B; code.z=z; code.n=n; code.m=m; code.k=n-m;
code.H=sparse(ri,ci,ones(size(ri)),m,n);
code.rows=cell(m,1);
for r=1:m, code.rows{r}=find(code.H(r,:)).'; end
code.baseEdges=nnz(B>=0); code.edges=nnz(code.H);
end
