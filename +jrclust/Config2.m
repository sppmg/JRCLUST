classdef Config2 < dynamicprops
    %CONFIG JRCLUST session configuration
    % replacement for P struct

    %% OBJECT-LEVEL PROPERTIES
    properties (Hidden, SetAccess=private, SetObservable)
        isError;
        paramSet;
        oldParamSet;
        tempParams;
    end

    %% CONFIG FILE
    properties (SetObservable, SetAccess=private)
        configFile;
    end

    %% RECORDING(S) (to ease the transition)
    properties (Dependent, Hidden, SetObservable)
        singleRaw;  % formerly vcFile
        multiRaw;   % formerly csFile_merge
    end

    %% COMPUTED PARAMS
    properties (SetObservable, Dependent)
        bytesPerSample;             % byte count for each discrete sample
        evtManualThreshSamp;        % evtManualThresh / bitScaling
        evtWindowRawSamp;           % interval around event to extract raw spike waveforms, in samples
        evtWindowSamp;              % interval around event to extract filtered spike waveforms, in samples
        nSites;                     % numel(siteMap)
        nSitesEvt;                  % 2*nSiteDir + 1 - nSitesExcl
        refracIntSamp;              % spike refractory interval, in samples
        sessionName;                % name of prm file, without path or extensions
    end

    %% LIFECYCLE
    methods
        function obj = Config2(filename)
            %CONFIG Construct an instance of this class
            if nargin == 0
                obj.configFile = '';
                userParams = struct();
            else
                filename_ = jrclust.utils.absPath(filename);
                userParams = jrclust.utils.mToStruct(filename_); % raises error if not a file
                obj.configFile = filename_;
            end

            obj.isError = 0;

            % for setting temporary parameters
            obj.tempParams = containers.Map();

            % read in default parameter set
            fid = fopen(fullfile(jrclust.utils.basedir(), 'params.json'), 'r');
            fullParams = jsondecode(fread(fid, '*char'));
            obj.paramSet = fullParams;
            fullParams = jrclust.utils.mergeStructs(fullParams.commonParameters, ...
                                                    fullParams.advancedParameters);
            fclose(fid);

            % read in mapping to old (v3) parameter set
            fid = fopen(fullfile(jrclust.utils.basedir(), 'old2new.json'), 'r');
            obj.oldParamSet = jsondecode(fread(fid, '*char'));
            fclose(fid);

            % set default parameters
            paramNames = fieldnames(fullParams);
            for i = 1:numel(paramNames)
                paramName = paramNames{i};
                if strcmp(paramName, 'rawRecordings')
                    continue;
                end
                [flag, val, errMsg] = obj.validateProp(paramName, fullParams.(paramName).default_value);
                if flag
                    obj.setProp(paramName, val);
                else
                    warning(errMsg);
                end
            end

            % overwrite default parameters with user-specified params
            if isfield(userParams, 'template_file') && ~isempty(userParams.template_file)
                try
                    userTemplate = jrclust.utils.mToStruct(jrclust.utils.absPath(userParams.template_file));
                    fns = fieldnames(userParams);
                    for i = 1:numel(fns) % merge userParams (specific) into userTemplate (general)
                        userTemplate.(fns{i}) = userParams.(fns{i});
                    end
                    userParams = userTemplate;
                catch ME
                    obj.warning(sprintf('Could not set template file %s: %s ', userParams.template_file, ME.message), 'Missing template file');
                end
            end

            % set batchMode first because it is used in the loop
            if isfield(userParams, 'batchMode')
                [flag, val, errMsg] = obj.validateProp('batchMode', userParams.batchMode);
                if flag
                    obj.setProp('batchMode', val);
                else
                    warning(errMsg);
                end

                userParams = rmfield(userParams, 'batchMode');
            end

            % load probe from a probe file (legacy support)
            if isfield(userParams, 'probe_file') && ~isempty(userParams.probe_file)
                % first check local directory
                pf = jrclust.utils.absPath(userParams.probe_file, fileparts(obj.configFile));
                if isempty(pf)
                    pf = jrclust.utils.absPath(userParams.probe_file, fullfile(jrclust.utils.basedir(), 'probes'));
                end
                if isempty(pf)
                    obj.error(sprintf('Could not find probe file ''%s''', userParams.probe_file));
                end

                probe = doLoadProbe(pf);
                probeFields = fieldnames(probe);

                for i = 1:numel(probeFields)
                    fn = probeFields{i};
                    obj.(fn) = probe.(fn);
                end
            end

            % set user-specified params
            uParamNames = fieldnames(userParams);
            for i = 1:numel(uParamNames)
                paramName = uParamNames{i};

                % ignore configFile/template_file
                if ismember(paramName, {'configFile', 'vcFile_prm', 'template_file'})
                    continue;
                elseif strcmpi(paramName, 'vcFile') && isempty(userParams.vcFile)
                    continue;
                elseif strcmpi(paramName, 'csFile_merge') && isempty(userParams.csFile_merge)
                    continue;
                end

                % empty values in the param file take on their defaults
                if ~isempty(userParams.(paramName))
                    [flag, val, errMsg] = obj.validateProp(paramName, userParams.(paramName)); %#ok<ASGLU>
                    if flag
                        obj.setProp(paramName, val);
                    else % TODO: warn users after a grace period
                        % warning(errMsg);
                    end
                end
            end

            % validate params
            if size(obj.siteLoc, 1) ~= obj.nSites
                obj.error('Malformed probe geometry', 'Bad probe configuration');
                return;
            end

            if numel(obj.shankMap) ~= obj.nSites
                obj.error('Malformed shank indexing', 'Bad probe configuration');
                return;
            end

            if max(obj.siteMap) > obj.nChans
                obj.error('siteMap refers to channels larger than indexed by nChans', 'Bad probe configuration');
                return;
            end

            % nSiteDir and/or nSitesExcl may not have been specified
            if isempty(obj.nSiteDir) || isempty(obj.nSitesExcl)
                siteDists = pdist2(obj.siteLoc, obj.siteLoc);

                % max over all sites of number of neighbors in merge radius
                nNeighMrg = max(sum(siteDists <= obj.evtMergeRad)); % 11/7/17 JJJ: med to max

                if isempty(obj.nSitesExcl)
                    % max over all sites of number of neighbors in detect radius
                    nNeighDetect = max(sum(siteDists <= obj.evtDetectRad)); % 11/7/17 JJJ: med to max
                    nsd = (nNeighDetect - 1)/2;
                    obj.nSitesExcl = nNeighDetect - nNeighMrg; %#ok<MCNPR>
                else
                    nNeighDetect = nNeighMrg + obj.nSitesExcl;
                    nsd = (nNeighDetect - 1)/2;
                end

                if isempty(obj.nSiteDir)
                    obj.nSiteDir = nsd; %#ok<MCNPR>
                end
            end

            if obj.nSitesEvt <= 0
                obj.error('nSitesExcl is too large or nSiteDir is too small', 'Bad configuration');
            end

            obj.addprop('siteNeighbors');
            ignoreSites_ = find(ismember(obj.siteMap, obj.ignoreSites));
            sn = findSiteNeighbors(obj.siteLoc, 2*obj.nSiteDir + 1, ignoreSites_, obj.shankMap);
            obj.setProp('siteNeighbors', sn);

            % boost that gain
            obj.bitScaling = obj.bitScaling/obj.gainBoost; %#ok<MCNPR>
        end

        function obj = subsasgn(obj, prop, val)
            if strcmp(prop.type, '.')
                [flag, val, errMsg] = obj.validateProp(prop.subs, val);
                if flag
                    obj.setProp(prop.subs, val);
                else
                    error(errMsg);
                end
            end
        end

        function val = subsref(obj, prop)
            ptype = {prop.type};
            % get a property or call a function without parens
            if numel(ptype) == 1 && strcmp(prop.type, '.')
                propname = prop.subs;
                if isfield(obj.oldParamSet, propname)
                    propname = obj.oldParamSet.(propname);
                end

                if nargout > 0 || isprop(obj, propname)
                    val = obj.(propname);
                else
                    obj.(propname);
                end
            elseif numel(ptype) == 2 && jrclust.utils.isEqual(ptype, {'.', '()'})
                psubs = {prop.subs};
                fname = psubs{1};
                if numel(psubs) > 1
                    fargs = psubs{2};
                else
                    fargs = {};
                end

                if nargout > 0
                    val = obj.(fname)(fargs{:});
                else
                    obj.(fname)(fargs{:});
                end
            elseif numel(ptype) == 2 && jrclust.utils.isEqual(ptype, {'.', '{}'})
                psubs = {prop.subs};
                fname = psubs{1};
                if numel(psubs) > 1
                    fargs = psubs{2};
                else
                    fargs = {};
                end

                field = obj.(fname);
                if nargout > 0
                    val = field{fargs{:}};
                end
            end
        end
    end

    %% DOUBLE SECRET METHODS
    methods (Access = private, Hidden)
        function error(obj, emsg, varargin)
            %ERROR Raise an error
            obj.isError = 1;
            if obj.batchMode
                error(emsg);
            else
                errordlg(emsg, varargin{:});
            end
        end

        function setProp(obj, propname, val)
            %SETPROP Set a property
            if isfield(obj.oldParamSet, propname)
                propname = obj.oldParamSet.(propname);
            end

            fullParams = jrclust.utils.mergeStructs(obj.paramSet.commonParameters, ...
                                                    obj.paramSet.advancedParameters);
            if isfield(fullParams, propname)
                if ~isprop(obj, propname)
                    obj.addprop(propname);
                end

                obj.(propname) = val;
            elseif ismember(propname, {'singleRaw', 'multiRaw'}) % separate validation for these
                obj.(propname) = val;
            end            
        end

        function [flag, val, errMsg] = validateProp(obj, propname, val)
            %VALIDATEPROP Ensure a property is valid
            if isfield(obj.oldParamSet, propname) % map the old param name to the new one
                propname = obj.oldParamSet.(propname);
            end

            fullParams = jrclust.utils.mergeStructs(obj.paramSet.commonParameters, ...
                                                    obj.paramSet.advancedParameters);

            flag = 1;
            errMsg = '';
            if isfield(fullParams, propname)
                validData = fullParams.(propname).validation;
                classes = validData.classes;
                attributes = validData.attributes;

                if isempty(val) || isempty(attributes)
                    if ~any(cellfun(@(c) isa(val, c), classes))
                        flag = 0;
                    end

                    % this is a hack but maybe a necessary hack
                    if strcmp(propname, 'rawRecordings')
                        if ischar(val)
                            val = {val};
                        end

                        if ~isprop(obj, 'configFile')
                            addprop(obj, 'configFile');
                            obj.configFile = '';
                        end

                        % get absolute paths
                        basedir = fileparts(obj.configFile);
                        val_ = cellfun(@(fn) jrclust.utils.absPath(fn, basedir), val, 'UniformOutput', 0);
                        isFound = ~cellfun(@isempty, val_);
                        if ~all(isFound)
                            flag = 0;
                            errMsg = sprintf('%d/%d files not found', sum(isFound), numel(isFound));
                        else
                            val = val_;
                        end
                    end

                    return;
                end

                try
                    validateattributes(val, classes, attributes);

                    % transform val in some way
                    if isfield(validData, 'postapply')
                        hFun = eval(validData.postapply);
                        val = hFun(val);
                    end

                    % check additional constraints
                    if isfield(validData, 'postassert')
                        hFun = eval(validData.postassert);
                        assert(hFun(val));
                    end

                    if isfield(validData, "values")
                        disp(validData.values);
                    end
                catch ME
                    errMsg = sprintf('Could not set %s: %s', propname, ME.message);
                    flag = 0;
                end
            end
        end

        function warning(obj, wmsg, varargin)
            %WARNING Raise a warning
            if obj.batchMode
                warning(wmsg);
            else
                warndlg(wmsg, varargin{:});
            end
        end
    end

    %% USER METHODS
    methods
        function edit(obj)
            %EDIT Edit the config file
            edit(obj.configFile);
        end

        function val = getOr(obj, fn, dv)
            %GETOR GET set value `obj.(fn)` OR default value `dv` if unset or empty
            if nargin < 3
                dv = [];
            end

            if ~isprop(obj, fn) || isempty(obj.(fn))
                val = dv;
            else
                val = obj.(fn);
            end
        end

        function success = save(obj, filename, exportAdv, diffsOnly)
            %SAVE Write parameters to a file
            success = 0;

            if nargin < 2
                filename = obj.configFile;
            end
            if nargin < 3
                exportAdv = 0;
            end
            if nargin < 4
                diffsOnly = 0;
            end

            if isempty(filename) % passed an empty string or no config file
                filename = 'stdout';
            end

            if ~strcmpi(filename, 'stdout')
                filename_ = jrclust.utils.absPath(filename);
                if isempty(filename_)
                    error('Could not find ''%s''', filename);
                elseif isdir(filename)
                    error('''%s'' is a directory', filename);
                end

                filename = filename_;
            end

            if strcmpi(filename, 'stdout')
                fid = 1;
            else
                if isempty(obj.configFile) % bind configFile to this new path
                    obj.configFile = filename;
                end

                % file already exists, back it up!
                if exist(filename, 'file')
                    [~, ~, ext] = fileparts(filename);
                    backupFile = jrclust.utils.subsExt(filename, [ext, '.bak']);
                    try
                        copyfile(filename, backupFile);
                    catch ME % cowardly back out
                        warning(ME.identifier, 'Could not back up old file: %s', ME.message);
                        return;
                    end
                end

                [fid, errmsg] = fopen(filename, 'w');
                if fid == -1
                    warning('Could not open config file for writing: %s', errmsg);
                    return;
                end
            end

            paramsToExport = obj.paramSet.commonParameters;
            if exportAdv
                paramsToExport = jrclust.utils.mergeStructs(paramsToExport, obj.paramSet.advancedParameters);
            end

            % replace fields in paramsToExport with values in this object
            paramNames = fieldnames(paramsToExport);
            for i = 1:numel(paramNames)
                pn = paramNames{i};

                if jrclust.utils.isEqual(paramsToExport.(pn).default_value, obj.(pn))
                    if diffsOnly % don't export fields which have default values
                        paramsToExport = rmfield(paramsToExport, pn);
                    end
                else
                    paramsToExport.(pn).default_value = obj.(pn);
                end
            end

            % write the file
            paramNames = fieldnames(paramsToExport);
            sections = {'usage', 'execution', 'probe', 'recording file', ...
                        'preprocessing', 'spike detection', 'feature extraction', ...
                        'clustering', 'curation', 'display', 'trial', ...
                        'validation', 'preview', 'traces', 'lfp', 'aux channel'};
            new2old = struct();
            oldParams = fieldnames(obj.oldParamSet);
            for i = 1:numel(oldParams)
                pn = oldParams{i};
                new2old.(obj.oldParamSet.(pn)) = pn;
            end

            % write header
            progInfo = jrclust.utils.info;
            fprintf(fid, '%% %s parameters ', progInfo.program);
            if ~exportAdv
                fprintf(fid, '(common parameters only) ');
            end
            if diffsOnly
                fprintf(fid, '(default parameters not exported)');
            end
            fprintf(fid, '\n\n');

            % write sections
            for i = 1:numel(sections)
                section = sections{i};
                % no params have this section as primary, skip it
                if ~any(cellfun(@(pn) strcmp(section, paramsToExport.(pn).section{1}), paramNames))
                    continue;
                end

                fprintf(fid, '%% %s PARAMETERS\n', upper(section));

                for j = 1:numel(paramNames)
                    pn = paramNames{j};
                    pdata = paramsToExport.(pn);
                    if ~strcmpi(pdata.section{1}, section)
                        continue;
                    end

                    fprintf(fid, '%s = %s; %% ', pn, jrclust.utils.field2str(pdata.default_value));
                    if isfield(new2old, pn) % write old parameter name
                        fprintf(fid, '(formerly %s) ', new2old.(pn));
                    end
                    fprintf(fid, '%s', strrep(pdata.description, 'μ', char(956))); % \mu
                    if isempty(pdata.comment)
                        fprintf(fid, '\n');
                    else
                        fprintf(fid, ' (%s)\n', strrep(pdata.comment, 'μ', char(956))); % \mu
                    end
                end

                fprintf(fid, '\n');
            end

            if fid > 1
                fclose(fid);
            end

            success = 1;
        end

        function rd = recDurationSec(obj, recID)
            %RECDURATIONSECS Get duration of recording file(s) in seconds
            if nargin < 2 || isempty(recID)
                hRecs = cellfun(@(fn) jrclust.models.recording.Recording(fn, obj), obj.rawRecordings, 'UniformOutput', 0);
                rd = sum(cellfun(@(hR) hR.nSamples, hRecs))/obj.sampleRate;
            elseif recID < 1 || recID > numel(obj.rawRecordings)
                error('recording ID %d is invalid (there are %d recordings)', recID, numel(obj.rawRecordings));
            else
                hRec = jrclust.models.recording.Recording(obj.rawRecordings{recID}, obj);
                rd = hRec.nSamples/obj.sampleRate;
            end
        end

        function resetTemporaryParams(obj, prmKeys)
            %RESETTEMPORARYPARAMS Reset temporary parameters
            if nargin < 2 || isempty(prmKeys)
                prmKeys = keys(obj.tempParams);
            elseif nargin == 2
                if ischar(prmKeys)
                    prmKeys = {prmKeys};
                end
                % only try to reset parameters we actually have
                prmKeys = intersect(prmKeys, keys(obj.tempParams));
            end

            for i = 1:numel(prmKeys)
                fn = prmKeys{i};
                obj.(fn) = obj.tempParams(fn);
                remove(obj.tempParams, fn);
            end
        end

        function setTemporaryParams(obj, varargin)
            %SETTEMPORARYPARAMS Set temporary parameters to reset later
            prmKeys = varargin(1:2:end);
            prmVals = varargin(2:2:end);

            if numel(prmKeys) ~= numel(prmVals)
                warning('number of property names not equal to values; skipping');
                return;
            end

            for i = 1:numel(prmKeys)
                prmKey = prmKeys{i};

                % already set a temporary value for this parameter, reset
                % it or we'll lose the original
                if isKey(obj.tempParams, prmKey)
                    obj.resetTemporaryParams(prmKey);
                end
                try
                    obj.tempParams(prmKey) = obj.(prmKey); % save old value for later
                    obj.(prmKey) = prmVals{i};
                catch ME
                    remove(obj.tempParams, prmKey);
                    warning(ME.identifier, 'failed to set %s: %s', prmKey, ME.message);
                end
            end
        end
    end

    %% GETTERS/SETTERS
    methods
        % bytesPerSample
        function bp = get.bytesPerSample(obj)
            bp = jrclust.utils.typeBytes(obj.dataType);
        end

        % evtManualThreshSamp
        function mt = get.evtManualThreshSamp(obj)
            mt = obj.evtManualThresh / obj.bitScaling;
        end

        % evtWindowRawSamp
        function ew = get.evtWindowRawSamp(obj)
            if isprop(obj, 'evtWindowRaw') && isprop(obj, 'sampleRate')
                ew = round(obj.evtWindowRaw * obj.sampleRate / 1000);
            else
                ew = [];
            end
        end
        function set.evtWindowRawSamp(obj, ew)
            if ~isprop(obj, 'sampleRate')
                error('cannot convert without a sample rate');
            end

            if ~isprop(obj, 'evtWindowRaw')
                obj.addprop('evtWindowRaw');
            end
            obj.evtWindowRaw = ew * 1000 / obj.sampleRate; %#ok<MCNPR>
        end

        % evtWindowSamp
        function ew = get.evtWindowSamp(obj)
            if isprop(obj, 'evtWindow') && isprop(obj, 'sampleRate')
                ew = round(obj.evtWindow * obj.sampleRate / 1000);
            else
                ew = [];
            end
        end
        function set.evtWindowSamp(obj, ew)
            if ~isprop(obj, 'sampleRate')
                error('cannot convert without a sample rate');
            end

            if ~isprop(obj, 'evtWindow')
                obj.addprop('evtWindow');
            end
            obj.evtWindow = ew * 1000 / obj.sampleRate; %#ok<MCNPR>
        end

        % multiRaw
        function set.multiRaw(obj, mr)
            if ~isprop(obj, 'rawRecordings')
                addprop(obj, 'rawRecordings');
            end
            if ~isprop(obj, 'configFile')
                addprop(obj, 'configFile');
                obj.configFile = '';
            end

            if ischar(mr)
                obj.singleRaw = mr;
                return;
            end

            % check is a cell array
            assert(iscell(mr), 'multiRaw must be a cell array');

            % get absolute paths
            basedir = fileparts(obj.configFile);
            mr_ = cellfun(@(fn) jrclust.utils.absPath(fn, basedir), mr, 'UniformOutput', 0);
            isFound = cellfun(@isempty, mr_);
            if ~all(isFound)
                error('%d/%d files not found', sum(isFound), numel(isFound));
            end

            % validation done, just set prop
            obj.setProp('rawRecordings', mr_);
        end

        % nSites
        function ns = get.nSites(obj)
            if isprop(obj, 'siteMap')
                ns = numel(obj.siteMap);
            else
                ns = [];
            end
        end

        % nSitesEvt
        function ns = get.nSitesEvt(obj)
            if isprop(obj, 'nSiteDir') && isprop(obj, 'nSitesExcl')
                ns = 2*obj.nSiteDir - obj.nSitesExcl + 1;
            else
                ns = [];
            end
        end

        % refracIntSamp
        function ri = get.refracIntSamp(obj)
            if isprop(obj, 'refracInt') && isprop(obj, 'sampleRate')
                ri = round(obj.refracInt * obj.sampleRate / 1000);
            else
                ri = [];
            end
        end
        function set.refracIntSamp(obj, ri)
            if ~isprop(obj, 'sampleRate')
                error('cannot convert without a sample rate');
            end

            if ~isprop(obj, 'refracInt')
                obj.addprop('refracInt');
            end
            obj.refracInt = ri * 1000 / obj.sampleRate; %#ok<MCNPR>
        end

        % sessionName
        function sn = get.sessionName(obj)
            if isprop(obj, 'configFile')
                [~, sn, ~] = fileparts(obj.configFile);
            else
                sn = '';
            end
        end

        % singleRaw
        function set.singleRaw(obj, sr)
            if ~isprop(obj, 'rawRecordings')
                addprop(obj, 'rawRecordings');
            end
            if ~isprop(obj, 'configFile')
                addprop(obj, 'configFile');
                obj.configFile = '';
            end

            if iscell(sr)
                obj.multiRaw = sr;
                return;
            end

            % check is a cell array
            assert(ischar(sr), 'singleRaw must be a string');

            % get absolute paths
            basedir = fileparts(obj.configFile);
            sr_ = jrclust.utils.absPath(sr, basedir);
            if isempty(sr_)
                error('''%s'' not found', sr);
            end

            % validation done, just set prop
            obj.setProp('rawRecordings', {sr_});
        end
    end
end
