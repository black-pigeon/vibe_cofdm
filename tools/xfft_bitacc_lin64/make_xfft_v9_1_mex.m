%Compile the xfft_v9_1_bitacc MEX function for the current Matlab environment
%  make_xfft_v9_1_bitacc_mex()
%
function []=make_xfft_v9_1_mex()

	platform=get_platform();
	fprintf('INFO:Building for platform %s\n',platform);

	%Check that directories and files required exist
	if (~isfile('xfft_v9_1_bitacc_cmodel.h')) error('ERROR:Could not find file xfft_v9_1_bitacc_cmodel.h'); end
	if (~isfile('xfft_v9_1_bitacc_mex.cpp' )) error('ERROR:Could not find file xfft_v9_1_bitacc_mex.cpp'); end

	mex_cmd={};
	switch lower(platform)
		case 'nt64'
			mex_cmd={'-DWIN64' '-DNT'   '-DNDEBUG' '-D_USRDLL' '-O' 'xfft_v9_1_bitacc_mex.cpp' '-L.' '-lIp_xfft_v9_1_bitacc_cmodel' '-lgmp'};
		case 'lin64'
			mex_cmd={'-DLIN64' '-DUNIX' '-DNDEBUG' '-D_USRDLL' '-O' 'xfft_v9_1_bitacc_mex.cpp' '-L.' '-lIp_xfft_v9_1_bitacc_cmodel' '-lgmp'};
	end
	if (isempty(mex_cmd)) error('ERROR:Unsupported platform %s',platform); end

	err=mex(mex_cmd{:});
	if (err) error('ERROR:Build was unsuccessful'); end

	if (ispc())
		path_var='PATH';
		lib_file='dynamic link libraries';
	else
		path_var='LD_LIBRARY_PATH';
		lib_file='shared objects';
	end

	fprintf('INFO:Build was successful\n');
	fprintf('INFO:With the current Matlab path the following MEX function will be used:\n');
	fprintf('INFO:  %s\n',which('xfft_v9_1_bitacc_mex'));
	fprintf('INFO:\n');
	fprintf('INFO:To use the MEX function, Matlab must be able to find all %s used by the model\n',lib_file);
	fprintf('INFO:This can be achieved in two ways:\n');
	fprintf('INFO:  1) Add the directory containing the %s to the %s environment variable before staring Matlab\n',lib_file,path_var);
	fprintf('INFO:  2) Copy the %s to a directory that is already in the library search path\n',lib_file);

end

%Determine Xilinx platform Matlab is running on
function [platform]=get_platform()
	if (ispc())
		platform='nt64';
	elseif (isunix())
		platform='lin64';
	else
		error('ERROR:Unexpected platform; must be one of PC or UNIX')
	end
end

%Check is a file exists or not
function [x]=isfile(f)
	x=(exist(f,'file')==2);
end

%-----------------------------------------------------------------------------
%  (c) Copyright 2014 Xilinx, Inc. All rights reserved.
%
%  This file contains confidential and proprietary information
%  of Xilinx, Inc. and is protected under U.S. and
%  international copyright and other intellectual property
%  laws.
%
%  DISCLAIMER
%  This disclaimer is not a license and does not grant any
%  rights to the materials distributed herewith. Except as
%  otherwise provided in a valid license issued to you by
%  Xilinx, and to the maximum extent permitted by applicable
%  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
%  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
%  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
%  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
%  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
%  (2) Xilinx shall not be liable (whether in contract or tort,
%  including negligence, or under any other theory of
%  liability) for any loss or damage of any kind or nature
%  related to, arising under or in connection with these
%  materials, including for any direct, or any indirect,
%  special, incidental, or consequential loss or damage
%  (including loss of data, profits, goodwill, or any type of
%  loss or damage suffered as a result of any action brought
%  by a third party) even if such damage or loss was
%  reasonably foreseeable or Xilinx had been advised of the
%  possibility of the same.
%
%  CRITICAL APPLICATIONS
%  Xilinx products are not designed or intended to be fail-
%  safe, or for use in any application requiring fail-safe
%  performance, such as life-support or safety devices or
%  systems, Class III medical devices, nuclear facilities,
%  applications related to the deployment of airbags, or any
%  other applications that could lead to death, personal
%  injury, or severe property or environmental damage
%  (individually and collectively, "Critical
%  Applications"). Customer assumes the sole risk and
%  liability of any use of Xilinx products in Critical
%  Applications, subject only to applicable laws and
%  regulations governing limitations on product liability.
%
%  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
%  PART OF THIS FILE AT ALL TIMES.
%-----------------------------------------------------------------------------
