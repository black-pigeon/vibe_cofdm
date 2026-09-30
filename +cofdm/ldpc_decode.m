function [u,ok,it,post] = ldpc_decode(llr,code,c)
% Layered normalized min-sum, positive LLR means bit 0.
% Float reference plus quantized-message experiment (not full RTL model).
post=clip(double(llr(:)),31.75);
assert(numel(post)==code.n);
if c.quantizedDecoder, post=clip(round(post*4)/4,15.75); end
messages=cell(code.m,1);
for r=1:code.m, messages{r}=zeros(size(code.rows{r})); end
ok=false;
for it=1:c.ldpcIterations
    for r=1:code.m
        ix=code.rows{r}; q=post(ix)-messages{r};
        if c.quantizedDecoder, q=clip(round(q*4)/4,63.75); end
        sg=ones(size(q)); sg(q<0)=-1;
        a=abs(q); [v1,j]=min(a); a(j)=Inf; v2=min(a);
        mag=repmat(v1,size(q)); mag(j)=v2;
        msg=c.ldpcAlpha*prod(sg)*sg.*mag;
        if c.quantizedDecoder, msg=clip(round(msg*4)/4,15.75); end
        post(ix)=q+msg;
        if c.quantizedDecoder, post(ix)=clip(round(post(ix)*4)/4,63.75); end
        messages{r}=msg;
    end
    if ~any(mod(code.H*double(post<0),2)), ok=true; break; end
end
u=post(1:code.k)<0;
end
function y=clip(x,a)
y=max(-a,min(a,x));
end
