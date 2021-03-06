function m = addInputMassActionAmount(m, name, compartment, default)
%AddInput Add an input species to a Model.MassActionAmount
%
%   m = AddInput(m, name, compartment, default)
%
%   Inputs
%   m: [ model struct scalar ]
%       The model to which the input species will be added
%   name: [ string ]
%       A name for the input. This is the name by which reactions will
%       refer to it.
%   compartment: [ string ]
%       The name of the compartment to which it will be added.
%   default: [ nonnegative scalar {0} ]
%       The default value for this input.
%
%   Outputs
%   m: [ model struct scalar ]
%       The model with the new input added.

% (c) 2015 David R Hagen & Bruce Tidor
% This work is released under the MIT license.

% Clean-up inputs
if nargin < 4
    default = [];
end

% Increment counter
nu = m.nu + 1;
m.nu = nu;
m.Inputs = growInputs(m.Inputs, nu);

% Add item
m.Inputs(nu).Name         = fixSpeciesName(name);
m.Inputs(nu).Compartment  = fixCompartmentName(compartment);
m.Inputs(nu).DefaultValue = fixInputDefaultValue(default);

m.Ready = false;
