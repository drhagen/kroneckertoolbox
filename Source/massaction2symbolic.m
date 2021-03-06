function symbolic = massaction2symbolic(m, opts)
% Inputs:
%   m [ Model.MassActionAmount struct ]
%   opts [ options struct ]
%       Options struct allowing the following fields:
%       .Verbose [ nonnegative integer ]
%           The level of debug information verbosity, with higher values giving
%           more output.
%
% Outputs:
%   symbolic [ Model.Symbolic struct ]

if nargin < 2
    opts = [];
end

% Default options
opts_.Verbose = 0;
opts_.Finalized = false;

opts = mergestruct(opts_, opts);

verbose = logical(opts.Verbose);

%% Assign reaction names if missing
nr = m.nr;
for i = 1:nr
    if isempty(m.Reactions(i).Name)
        m.Reactions(i).Name = ['rxn_' num2str(i)];
    end
end

nradd = m.add.nr;
for i = 1:nradd
    if isempty(m.add.Reactions(i).Name)
        m.add.Reactions(i).Name = ['rxn_' num2str(nr+i)];
    end
end

%% Extract model components
if verbose; fprintf('Extracting model components...'); end

%% Compartments
nv     = m.nv;
vNames = {m.Compartments.Name}';
vIDs   = cellfun(@(x)genUID, vNames, 'UniformOutput', false);
v      = [m.Compartments.Size]';
dv     = [m.Compartments.Dimension]';

%% States
nx      = m.nx;
xNames  = {m.States.Name}';
xIDs    = cellfun(@(x)genUID, xNames, 'UniformOutput', false);
xvNames = {m.States.Compartment}';
x       = cell(nx,1); % linear combinations of seeds
for i = 1:nx
    x0 = m.States(i).InitialValue; % cell array of [seed name, coefficient] rows
    nsx0 = size(x0,1);
    xi = '';
    for j = 1:nsx0
        seedName = x0{j,1};
        seedCoef = x0{j,2};
        if regexp(seedName, '\W') % wrap in quotes if invalid chars present in state name
            seedName = ['"', seedName, '"'];
        end
        
        if j ~= 1 % Don't add + to 1st term
            xi = [xi, ' + '];
        end
        
        if seedCoef == 1 % Clean version if coefficient = 1
            xi = [xi seedName];
        else
            xi = [xi seedCoef '*' seedName];
        end
    end
    
    x{i} = xi;
end

%% Inputs
nu      = m.nu;
uNames  = {m.Inputs.Name}';
uIDs    = cellfun(@(x)genUID, uNames, 'UniformOutput', false);
uvNames = {m.Inputs.Compartment}';
u       = [m.Inputs.DefaultValue]';
% Handle blank inputs
if nu == 0
    uNames  = cell(0,1);
    uIDs    = cell(0,1);
    uvNames = cell(0,1);
    u       = zeros(0,1);
end

% Make combined states/inputs names and compartments for convenience
xuNames  = [xNames; uNames];
xuvNames = [xvNames; uvNames];

%% Seeds
ns      = m.ns;
sNames  = {m.Seeds.Name}';
sIDs    = cellfun(@(x)genUID, sNames, 'UniformOutput', false);
s       = [m.Seeds.Value]';
% Handle blank seeds
if ns == 0
    sNames  = cell(0,1);
    sIDs    = cell(0,1);
    s       = zeros(0,1);
end

%% Parameters
nk      = m.nk;
kNames  = {m.Parameters.Name}';
kIDs    = cellfun(@(x)genUID, kNames, 'UniformOutput', false);
k       = [m.Parameters.Value]';

%% Reactions
%   Each reaction is a microscopic reaction (forward/reverse are kept separate)
%   TODO: potentially search for and combine forward and reverse reactions
nr      = m.nr;
rNames  = {m.Reactions.Name}';
rIDs    = cellfun(@(x)genUID, rNames, 'UniformOutput', false);
r = cell(nr,3);
for i = 1:nr
    
    reaction = m.Reactions(i);
    
    reactants = reaction.Reactants;
    products = reaction.Products;
    
    % Assemble rate expression from cell array of [parameter, coefficient] rows
    %   and reactants according to law of mass action
    % A valid reaction only has 1 parameter
    param = reaction.Parameter;
    paramName = param{1};
    paramCoef = param{2};
    
    if regexp(paramName, '\W') % wrap in quotes if invalid chars present in state name
        paramName = ['"', paramName, '"'];
    end
    
    if paramCoef == 1
        rate = paramName;
    else
        rate = [paramCoef '*' paramName];
    end
    
    nReactants = length(reaction.Reactants);
    for j = 1:nReactants
        reactant = reaction.Reactants{j};
        if isempty(reactant) % shouldn't be necessary
            continue
        end
        
        % Prefix species name with compartment name if it doesn't already have it
        % Make sure compartment name is valid if it does
        compartment = xuvNames{ismember(xuNames, reactant)};
        if isempty(regexp(reactant, '\.', 'once'))
            reactant = [compartment '.' reactant];
        else
            parts = strsplit(reactant, '.');
            assert(length(parts) == 2, 'massaction2symbolic:badReactantName', 'Reactant %s has too many parts', reactant)
            compartmentInReactant = strrep(parts{1}, '"', '');
            assert(strcmp(compartment, compartmentInReactant), 'massaction2symbolic:compartmentNotMatchReactant', 'Reactant with full name %s doesn''t match listed compartment %s', reactant, compartment)
        end
        
        % Wrap in quotes if invalid chars (excluding the dot) present in full reactant name
        if regexp(reactant, '[^\w\.]') 
            reactant = ['"', reactant, '"'];
        end
        rate = [rate '*' reactant];
    end
    
    r(i,:) = {reactants, products, rate};
end

%% Rules
nz      = m.nz;
zNames  = {m.Rules.Name}';
zIDs    = {m.Rules.ID}';
z = cell(nz,3);
for i = 1:nz
    rule = m.Rules(i);
    
    % Check rule type validity
    switch rule.Type
        case 'repeated assignment'
            % pass
        case 'initial assignment'
            % pass
        otherwise
            warning('analytic2symbolic: rule %s of type %s not recognized. Ignoring.', rule.Name, rule.Type)
    end
    
    z(i,:) = {rule.Target, rule.Expression, rule.Type};
end
% Remove invalid, empty rule spots
zInvalid = cellfun(@isempty,z(:,3));
nz = nz - sum(zInvalid);
zNames(zInvalid) = [];
zIDs(zInvalid)   = [];
z(zInvalid,:)    = [];
% Handle blank rules
if nz == 0
    zNames = cell(0,1);
    zIDs   = cell(0,1);
end

if verbose; fprintf('done.\n'); end

%% Assemble symbolic model
if verbose; fprintf('Assembling symbolic model...'); end

symbolic = [];

symbolic.Type = 'Model.Symbolic';
symbolic.Name = m.Name;

symbolic.nv     = nv;
symbolic.vNames = vNames;
symbolic.vIDs   = vIDs;
symbolic.v      = v; % doubles
symbolic.dv     = dv;

symbolic.nx      = nx;
symbolic.xNames  = xNames;
symbolic.xIDs    = xIDs;
symbolic.xvNames = xvNames;
symbolic.x       = x; % cell array of strings

symbolic.nu      = nu;
symbolic.uNames  = uNames;
symbolic.uIDs    = uIDs;
symbolic.uvNames = uvNames;
symbolic.u       = u; % doubles

symbolic.ns     = ns;
symbolic.sNames = sNames;
symbolic.sIDs   = sIDs;
symbolic.s      = s; % doubles

symbolic.nk     = nk;
symbolic.kNames = kNames;
symbolic.kIDs   = kIDs;
symbolic.k      = k; % doubles

symbolic.nr     = nr;
symbolic.rNames = rNames;
symbolic.rIDs   = rIDs;
symbolic.r      = r; % cell matrix

symbolic.nz     = nz;
symbolic.zNames = zNames;
symbolic.zIDs   = zIDs;
symbolic.z      = z; % cell matrix

if verbose; fprintf('done.\n'); end

end