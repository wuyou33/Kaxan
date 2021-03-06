% sys_id.m     e.anderlini@ucl.ac.uk     23/01/2017
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This script is used to identify a linear model of the Kaxan ROV.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear;
close all;

%% Load the data to be fitted:
load('tmp_rov_mpc.mat');
dt = t(2)-t(1);
tEnd = t(end);

%% Prepare the data for system identification:
nu = 5;     % no. input variables
nx = 8;     % no. states
% Keep only 4 DOF:
x_4dof = [x(:,1:3),x(:,6:9),x(:,12)];
f_4dof = [f(:,1:3),f(:,6)];
d = [t(1:101).^2;ones(size(f_4dof,1)-101,1)];    % hydrostatics disturbance
simin = [t,f_4dof,d,x_4dof];
% simin = [t,f_4dof,x_4dof];

%% Load the ROV data:
load('rov.mat');

%% Generate the LTI model of the Kaxan ROV in 4 DOF:
M = [rov.M_B(1:3,1:3),rov.M_B(1:3,6);rov.M_B(6,1:3),rov.M_B(6,6)] + ...
    [rov.M_A(1:3,1:3),rov.M_A(1:3,6);rov.M_A(6,1:3),rov.M_A(6,6)];
D = [rov.D_l(1:3,1:3),rov.D_l(1:3,6);rov.D_l(6,1:3),rov.D_l(6,6)];
G = zeros(4);
M_inv = pinv(M);
A = [zeros(4),eye(4);-M_inv*G,-M_inv*D];
B = [zeros(4);M_inv];
E = [zeros(4);M_inv];
C = eye(8);
D = zeros(8,4);
% A = zeros(8);
% B = zeros(8,4);

% Specify values for Q and R:
Q = 0.05*eye(8);
R = 0.05*eye(8);

% Increase the size of the input matrix to account for hydrostatics:
B = [B,zeros(8,1)];
B(7,5) = 0.25;
D = zeros(8,5);
% A = [zeros(4),eye(4);zeros(4),-0.5*eye(4)];
% A(8,8) = -5;
% B = [zeros(4);0.01*eye(4)];
% B(8,4) = 0.2;

%% Prepare a state-space model with identifiable parameters structure:
init_sys = idss(A,B,C,D,'Ts',0);  % continuous-time state-space model
% Constrain some parameters:
init_sys.Structure.A.Free(1:4,:) = false;
init_sys.Structure.A.Free(5:8,1:4) = false;
init_sys.Structure.B.Free(1:4,:) = false;
% init_sys.Structure.B.Free(1:6,5) = false;
% init_sys.Structure.B.Free(8,5) = false;
init_sys.Structure.C.Free = false;
init_sys.Structure.D.Free = false;

% Define the data range to be used:
s = 1;
e = 1001;

% Initialize data object:
data = iddata(x_4dof(s:e,:),[f_4dof(s:e,:),d(s:e,:)],dt);
% data = iddata(x_4dof(s:e,:),f_4dof(s:e,:),dt);

% Estimate the values of the state-space model:
sys = ssest(data,init_sys);

%% Test the predicted values with a Kalman filter:
% Extract the values:
A = sys.A;
B = sys.B;
C = sys.C;
% Simulink file:
sfile = 'kal_fil';
% Load the Simulink file:
load_system(sfile);
% Run the Simulink file:
sout = sim(sfile,'StopTime',num2str(tEnd));
% Close the Simulink file:
close_system(sfile);

% Extract the data to be plotted:
x_hat = sout.get('logsout').getElement('x_hat').Values.Data;
% Plot the data:
sysid_plot(t,x_4dof,x_hat);