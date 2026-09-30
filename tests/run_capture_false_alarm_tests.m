function run_capture_false_alarm_tests()
% Regression tests for the multi-stage capture decision.
addpath(fileparts(fileparts(mfilename('fullpath'))));
p=struct('ltf_score_min',0.12,'ltf_min_offset',64,'ltf_max_offset',384,...
    'ltf_to_frame_offset',192,'ltf_timeout',32,'fine_timeout',8,...
    'header_timeout',16,'holdoff',4,'lock_timeout',1000);

% Normal frame: STF -> accepted LTF -> fine CFO -> good header.
e=blank(80); e.stf_hit(3)=1; e.stf_index(3)=100;
e.ltf_peak_valid(12)=1; e.ltf_peak_score(12)=0.80; e.ltf_peak_index(12)=292;
e.fine_cfo_valid(14)=1; e.header_crc_valid(16)=1; e.header_crc_ok(16)=1;
[o,f]=cofdm.capture_state(e,p);
assert(o.candidate_valid(3) && o.coarse_cfo_enable(3));
assert(o.ltf_start(12) && o.fine_cfo_enable(12));
assert(o.frame_valid(16) && any(o.capture_locked(16:end)));
assert(f.frame_start_index==100);

% STF-only candidate must time out and never lock.
e=blank(60); e.stf_hit(2)=1; e.stf_index(2)=20;
[o,f]=cofdm.capture_state(e,p);
assert(any(o.capture_timeout) && ~any(o.frame_valid) && f.false_alarm_count==1);

% Periodic false STF plus a weak/illegal LTF must be rejected.
e=blank(80); e.stf_hit([2 45])=1; e.stf_index([2 45])=[10 200];
e.ltf_peak_valid(8)=1; e.ltf_peak_score(8)=0.01; e.ltf_peak_index(8)=30;
[o,f]=cofdm.capture_state(e,p);
assert(~any(o.frame_valid) && f.false_alarm_count>=1);

% Correct LTF but bad header must not become a valid frame.
e=blank(80); e.stf_hit(2)=1; e.stf_index(2)=100;
e.ltf_peak_valid(8)=1; e.ltf_peak_score(8)=0.8; e.ltf_peak_index(8)=292;
e.fine_cfo_valid(10)=1; e.header_crc_valid(12)=1; e.header_crc_ok(12)=0;
[o,f]=cofdm.capture_state(e,p);
assert(~any(o.frame_valid) && f.false_alarm_count==1);

% A locked frame is released by frame_done and a new candidate is accepted
% only after the holdoff window.
e=blank(100); e.stf_hit(2)=1; e.stf_index(2)=100;
e.ltf_peak_valid(8)=1; e.ltf_peak_score(8)=0.8; e.ltf_peak_index(8)=292;
e.fine_cfo_valid(10)=1; e.header_crc_valid(12)=1; e.header_crc_ok(12)=1;
e.frame_done(20)=1; e.stf_hit(25)=1; e.stf_index(25)=500;
[o,f]=cofdm.capture_state(e,p);
assert(sum(o.candidate_valid)==2 && sum(o.frame_valid)==1);

fprintf('PASS MATLAB capture false-alarm/state tests: candidates=%d false_alarms=%d\n',...
    sum(o.candidate_valid),f.false_alarm_count);
end

function e=blank(N)
e.sample_valid=true(N,1); e.stf_hit=false(N,1); e.stf_index=zeros(N,1);
e.ltf_peak_valid=false(N,1); e.ltf_peak_score=zeros(N,1); e.ltf_peak_index=zeros(N,1);
e.fine_cfo_valid=false(N,1); e.header_crc_valid=false(N,1); e.header_crc_ok=false(N,1);
e.frame_abort=false(N,1); e.frame_done=false(N,1);
end
