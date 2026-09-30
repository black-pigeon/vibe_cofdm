function [log, final] = capture_state(ev, p)
%CAPTURE_STATE Golden model for the multi-stage PHY capture sequencer.
if nargin < 2, p = struct(); end
p = defaults(p);
N = infer_length(ev);
sample_valid     = field_or(ev,'sample_valid',true(N,1));
stf_hit          = field_or(ev,'stf_hit',false(N,1));
stf_index        = field_or(ev,'stf_index',zeros(N,1));
ltf_peak_valid   = field_or(ev,'ltf_peak_valid',false(N,1));
ltf_peak_score   = field_or(ev,'ltf_peak_score',zeros(N,1));
ltf_peak_index   = field_or(ev,'ltf_peak_index',zeros(N,1));
fine_cfo_valid   = field_or(ev,'fine_cfo_valid',false(N,1));
header_crc_valid = field_or(ev,'header_crc_valid',false(N,1));
header_crc_ok    = field_or(ev,'header_crc_ok',false(N,1));
frame_abort      = field_or(ev,'frame_abort',false(N,1));
frame_done       = field_or(ev,'frame_done',false(N,1));

out=struct();
out.candidate_valid=false(N,1);
out.coarse_cfo_enable=false(N,1);
out.ltf_start=false(N,1);
out.fine_cfo_enable=false(N,1);
out.header_enable=false(N,1);
out.frame_start=false(N,1);
out.frame_valid=false(N,1);
out.capture_locked=false(N,1);
out.capture_timeout=false(N,1);
out.false_alarm_count=zeros(N,1,'uint32');
out.frame_start_index=zeros(N,1);
out.ltf_start_index=zeros(N,1);
out.state=zeros(N,1,'uint8');

% State encoding is identical to cofdm_capture_ctrl.sv.
IDLE=uint8(0); LTF_SEARCH=uint8(1); FINE_WAIT=uint8(2);
HEADER_WAIT=uint8(3); LOCKED=uint8(4); HOLDOFF=uint8(5);
st=IDLE; timer=0; false_count=uint32(0); holdoff=0;
candidate_index=0; ltf_index=0; frame_index=0;

for n=1:N
    if sample_valid(n)
        switch st
            case IDLE
                timer=0;
                if stf_hit(n)
                    candidate_index=stf_index(n);
                    out.candidate_valid(n)=true;
                    out.coarse_cfo_enable(n)=true;
                    st=LTF_SEARCH; timer=0;
                end
            case LTF_SEARCH
                timer=timer+1;
                if ltf_peak_valid(n)
                    legal=ltf_peak_index(n)>=candidate_index+p.ltf_min_offset && ...
                        ltf_peak_index(n)<=candidate_index+p.ltf_max_offset;
                    strong=ltf_peak_score(n)>=p.ltf_score_min;
                    if legal && strong
                        ltf_index=ltf_peak_index(n);
                        frame_index=ltf_index-p.ltf_to_frame_offset;
                        out.ltf_start(n)=true;
                        out.fine_cfo_enable(n)=true;
                        out.frame_start(n)=true;
                        out.ltf_start_index(n)=ltf_index;
                        out.frame_start_index(n)=frame_index;
                        st=FINE_WAIT; timer=0;
                    else
                        false_count=false_count+1;
                        st=HOLDOFF; timer=0; holdoff=0;
                    end
                elseif timer>=p.ltf_timeout
                    false_count=false_count+1;
                    out.capture_timeout(n)=true;
                    st=HOLDOFF; timer=0; holdoff=0;
                end
            case FINE_WAIT
                timer=timer+1;
                if fine_cfo_valid(n)
                    st=HEADER_WAIT; timer=0;
                elseif timer>=p.fine_timeout
                    false_count=false_count+1;
                    out.capture_timeout(n)=true;
                    st=HOLDOFF; timer=0; holdoff=0;
                end
            case HEADER_WAIT
                timer=timer+1;
                out.header_enable(n)=true;
                if header_crc_valid(n)
                    if header_crc_ok(n)
                        out.frame_valid(n)=true;
                        st=LOCKED; timer=0;
                    else
                        false_count=false_count+1;
                        st=HOLDOFF; timer=0; holdoff=0;
                    end
                elseif timer>=p.header_timeout
                    false_count=false_count+1;
                    out.capture_timeout(n)=true;
                    st=HOLDOFF; timer=0; holdoff=0;
                end
            case LOCKED
                out.capture_locked(n)=true; timer=timer+1;
                if frame_abort(n)||frame_done(n)||timer>=p.lock_timeout
                    st=HOLDOFF; timer=0; holdoff=0;
                end
            case HOLDOFF
                timer=timer+1;
                if timer>=p.holdoff, st=IDLE; timer=0; end
        end
    end
    if st==LOCKED, out.capture_locked(n)=true; end
    out.false_alarm_count(n)=false_count;
    out.state(n)=st;
end
log=out;
final=struct('state',st,'candidate_index',candidate_index,'ltf_index',ltf_index,...
    'frame_start_index',frame_index,'false_alarm_count',false_count);
end

function p=defaults(p)
if ~isfield(p,'ltf_score_min'), p.ltf_score_min=0.12; end
if ~isfield(p,'ltf_min_offset'), p.ltf_min_offset=64; end
if ~isfield(p,'ltf_max_offset'), p.ltf_max_offset=384; end
if ~isfield(p,'ltf_to_frame_offset'), p.ltf_to_frame_offset=192; end
if ~isfield(p,'ltf_timeout'), p.ltf_timeout=512; end
if ~isfield(p,'fine_timeout'), p.fine_timeout=128; end
if ~isfield(p,'header_timeout'), p.header_timeout=512; end
if ~isfield(p,'lock_timeout'), p.lock_timeout=2^31-1; end
if ~isfield(p,'holdoff'), p.holdoff=256; end
end

function x=field_or(s,name,default)
if isfield(s,name), x=s.(name); else, x=default; end
x=x(:);
end

function N=infer_length(ev)
names={'sample_valid','stf_hit','ltf_peak_valid','fine_cfo_valid','header_crc_valid','frame_abort','frame_done'};
N=0;
for k=1:numel(names)
    if isfield(ev,names{k}), N=max(N,numel(ev.(names{k}))); end
end
if N==0, error('capture_state:empty','At least one event vector is required'); end
end
