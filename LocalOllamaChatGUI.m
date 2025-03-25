function LocalOllamaChatGUI
close all force hidden;
clc;
evalin('base', 'clear;');

% Create main figure
fig = uifigure('Name', 'Local Ollama Chat', 'Position', [100 100 1000 700]);
movegui(fig, 'center');

% Initialize UserData with default settings
fig.UserData = struct(...
    'apiUrl', "http://localhost:11434/api/generate",...
    'httpOptions', weboptions('MediaType', 'application/json',...
    'RequestMethod', 'post',...
    'ArrayFormat', 'json',...
    'Timeout', 300),...
    'messages', struct('role', {'system'}, 'content', {'You are a helpful assistant.'}),...
    'currentFiles', {{}},...
    'model', 'llama3.2-vision:latest',...
    'systemPrompt', 'You are a helpful assistant.',...
    'modelOptions', struct(...
    'temperature', 0.5,...
    'top_p', 0.5,...
    'top_k', 40,...
    'num_ctx', 2048,...
    'seed', 0,...
    'num_predict', 128  ));

% Chat history display
historyBox = uitextarea(fig,...
    'Position', [20 180 960 500],...
    'Editable', false,...
    'WordWrap', true,...
    'FontSize', 12,...
    'BackgroundColor', [1 1 1]);

% File upload panel
filePanel = uipanel(fig, 'Title', 'File Upload',...
    'Position', [20 35 400 140],...
    'BackgroundColor', [0.95 0.95 0.95]);

uibutton(filePanel, 'push',...
    'Text', 'Browse Files',...
    'Position', [10 80 100 30],...
    'ButtonPushedFcn', @(btn,event) browseFiles);

fig.UserData.fileList = uilistbox(filePanel,...
    'Position', [120 10 270 100],...
    'Multiselect', 'on');

% Input panel
inputPanel = uipanel(fig, 'Title', 'Chat Input',...
    'Position', [430 35 550 140],...
    'BackgroundColor', [0.95 0.95 0.95]);

inputField = uieditfield(inputPanel, 'text',...
    'Position', [10 10 400 100],...
    'Placeholder', 'Type your message here...',...
    'FontSize', 12);

sendButton = uibutton(inputPanel, 'push',...
    'Text', 'Send',...
    'Position', [420 70 115 40],...
    'FontSize', 14,...
    'BackgroundColor', [0.3 0.6 1],...
    'FontColor', [1 1 1],...
    'ButtonPushedFcn', @(btn,event) sendMessage);

% Control buttons
uibutton(inputPanel, 'push',...
    'Text', 'New Chat',...
    'Position', [440 10 70 20],...
    'FontSize', 12,...
    'BackgroundColor', [0.4 0.8 0.4],...
    'FontColor', [1 1 1],...
    'ButtonPushedFcn', @(btn,event) handleNewChat);

uibutton(fig, 'push',...
    'Text', 'Settings',...
    'Position', [880 670 100 25],...
    'FontSize', 12,...
    'BackgroundColor', [0.8 0.8 0.8],...
    'ButtonPushedFcn', @(btn,event) openSettings(fig));

% Callback functions
    function browseFiles
        [files, path] = uigetfile(...
            {'*.png;*.jpg;*.jpeg;*.pdf;*.docx;*.txt',...
            'Supported Files (*.png, *.jpg, *.pdf, *.docx, *.txt)'},...
            'MultiSelect', 'on');

        if ~isequal(files, 0)
            if ischar(files)
                files = {files};
            end
            fullpaths = fullfile(path, files);
            fig.UserData.currentFiles = fullpaths;
            fig.UserData.fileList.Items = cellstr(files);
        end
    end

    function sendMessage
        prompt = inputField.Value;
        files = fig.UserData.currentFiles;

        if isempty(prompt) && isempty(files)
            return;
        end

        % Disable the Send button and show "Busy" text
        sendButton.Enable = 'off';
        busyText = uilabel(inputPanel, 'Text', 'Busy..',...
            'Position', [420 40 115 20],...
            'FontSize', 12,...
            'FontColor', [1 0 0],...
            'HorizontalAlignment', 'center');

        % Update GUI with user prompt immediately
        if ~isempty(prompt)
            updateHistory('user', prompt);
        end
        if ~isempty(files)
            for i = 1:length(files)
                updateHistory('system', ['Uploaded file: ' files{i}]);
            end
        end

        % Clear input fields
        inputField.Value = '';
        fig.UserData.currentFiles = {};
        fig.UserData.fileList.Items = {};

        % Process message asynchronously
        drawnow; % Force UI update
        processRequest(prompt, files, @() onRequestComplete(busyText));
    end

% function handleNewChat
%     LocalOllamaChatGUI
% end
    function handleNewChat
        % Reset chat history to initial state with current system prompt
        fig.UserData.messages = struct('role', {'system'}, 'content', {fig.UserData.systemPrompt});

        % Ensure historyBox.Value exists and is accessible
        if isprop(historyBox, 'Value')
            % Clear the chat history display (using proper empty value format)
            if isa(historyBox.Value, 'cell')
                historyBox.Value = {''}; % Prevent empty cell array error
            elseif isa(historyBox.Value, 'string')
                historyBox.Value = "";  % Assign empty string
            elseif isa(historyBox.Value, 'char')
                historyBox.Value = '';  % Assign empty character vector
            elseif isa(historyBox, 'matlab.ui.control.ListBox') || isa(historyBox, 'matlab.ui.control.DropDown')
                historyBox.Value = {''}; % Safe empty value for list-based UI components
            else
                warning('historyBox.Value type not recognized. Setting to default empty string.');
                historyBox.Value = ''; % Fallback to empty char
            end
        else
            warning('historyBox does not have a "Value" property.');
        end

        % Reset file upload components
        fig.UserData.currentFiles = {};
        fig.UserData.fileList.Items = {};

        % Optional: Add system message confirmation
        updateHistory('system', 'New chat session started');
    end


    function updateHistory(role, content)
        currentText = historyBox.Value;
        if isempty(currentText)
            currentText = {};
        elseif ischar(currentText)
            currentText = {currentText};
        end

        switch role
            case 'user'
                newEntries = {['You: ' content]};
            case 'assistant'
                separator = repmat('-', 1, 40);
                newEntries = {separator, ['Assistant: ' content], separator};
            case 'system'
                newEntries = {['System: ' content]};
        end

        historyBox.Value = [currentText; newEntries(:)];
        scroll(historyBox, 'bottom');
    end

    function processRequest(prompt, files, completionCallback)
        try
            % Process files
            fullPrompt = '';
            imageEncodings = {};

            if ~isempty(files)
                for i = 1:length(files)
                    [~, ~, ext] = fileparts(files{i});
                    if ismember(ext, {'.png', '.jpg', '.jpeg'})
                        base64Image = encode_image(files{i});
                        imageEncodings{end+1} = base64Image;
                    else
                        textContent = extractDocumentText(files{i});
                        fullPrompt = [fullPrompt ' [Document: ' textContent '] '];
                    end
                end
            end
            fullPrompt = [fullPrompt prompt];

            % Update system prompt if changed
            if ~strcmp(fig.UserData.messages(1).content, fig.UserData.systemPrompt)
                fig.UserData.messages(1).content = fig.UserData.systemPrompt;
            end

            % Add user message to history
            newUserMsg = struct('role', 'user', 'content', fullPrompt);
            fig.UserData.messages(end+1) = newUserMsg;

            % Build request with current settings
            data = struct(...
                'model', fig.UserData.model,...
                'prompt', buildPrompt(fig.UserData.messages),...
                'stream', false,...
                'options', fig.UserData.modelOptions...
                );

            % Add images if present
            if ~isempty(imageEncodings)
                data.images = imageEncodings;
            end

            % Send request with current timeout
            response = webwrite(fig.UserData.apiUrl, data, fig.UserData.httpOptions);
            aiResponse = response.response;

            % Update chat history
            updateHistory('assistant', aiResponse);
            newAiMsg = struct('role', 'assistant', 'content', aiResponse);
            fig.UserData.messages(end+1) = newAiMsg;

        catch ME
            updateHistory('system', ['Error: ' ME.message]);
        end

        % Call the completion callback to re-enable the Send button
        completionCallback();
    end

    function onRequestComplete(busyText)
        % Re-enable the Send button and remove "Busy" text
        sendButton.Enable = 'on';
        delete(busyText);
        drawnow; % Force UI update
    end

    function openSettings(parentFig)
        existingFigs = findall(0, 'Type', 'Figure', 'Name', 'Settings');
        if ~isempty(existingFigs)
            close(existingFigs);
        end

        settingsFig = uifigure('Name', 'Settings', 'Position', [300 300 550 600],...
            'CloseRequestFcn', @closeSettings);
        movegui(settingsFig, 'center');

        % Create tab group with space for save button
        tabGroup = uitabgroup(settingsFig, 'Position', [10 50 520 550]);

        % Connection Tab
        connTab = uitab(tabGroup, 'Title', 'Connection');
        createConnectionTab(connTab, parentFig, settingsFig);

        % Model Tab
        modelTab = uitab(tabGroup, 'Title', 'Model Settings');
        createModelTab(modelTab, parentFig, settingsFig);

        % Add global save button
        uibutton(settingsFig, 'push',...
            'Position', [235 10 100 30],...
            'Text', 'Save All',...
            'ButtonPushedFcn', @(src,event) saveAllSettings(parentFig, settingsFig));
        % Add global help button
        uibutton(settingsFig, 'push',...
            'Position', [485 578 40 20],...
            'Text', 'Help',...
            'ButtonPushedFcn', @(src,event) openHelpWindow());
    end

    function createConnectionTab(tab, parentFig, settingsFig)
        grid = uigridlayout(tab, [6 2]);
        grid.RowHeight = {'fit','fit','fit','fit','fit', 'fit'};
        grid.ColumnWidth = [120 350];
        grid.Padding = [10 10 10 10];

        % API URL
        uilabel(grid, 'Text', 'API URL:');
        apiUrlField = uieditfield(grid, 'text',...
            'Value', parentFig.UserData.apiUrl,...
            'Tag', 'apiUrl');
        apiUrlField.Layout.Row = 1;
        apiUrlField.Layout.Column = 2;

        % Timeout (fixed with proper tag)
        uilabel(grid, 'Text', 'Timeout (seconds):');
        timeoutField = uispinner(grid,...
            'Limits', [1 600],...
            'Value', parentFig.UserData.httpOptions.Timeout,...
            'Step', 1,...
            'Tag', 'timeoutSpinner');
        timeoutField.Layout.Row = 2;
        timeoutField.Layout.Column = 2;

        % Connection test
        testBtn = uibutton(grid, 'push',...
            'Text', 'Test Connection',...
            'ButtonPushedFcn', @testConnection);
        testBtn.Layout.Row = 3;
        testBtn.Layout.Column = [1 2];

        % Status indicators
        statusLight = uilamp(grid);
        statusLight.Layout.Row = 4;
        statusLight.Layout.Column = 1;

        statusText = uilabel(grid, 'Text', 'Not tested');
        statusText.Layout.Row = 4;
        statusText.Layout.Column = 2;

        function testConnection(~,~)
            try
                tempOptions = weboptions(...
                    'RequestMethod', 'get',...
                    'Timeout', timeoutField.Value);

                testUrl = strrep(apiUrlField.Value, '/api/generate', '/api/tags');
                response = webread(testUrl, tempOptions);

                if isfield(response, 'models')
                    statusLight.Color = [0 1 0];
                    statusText.Text = sprintf('Connected! Found %d models', numel(response.models));

                else
                    error('Invalid response format');

                end
            catch ME
                statusLight.Color = [1 0 0];
                statusText.Text = ['Connection failed: ' ME.message];

                % Create a new figure window (popup window)
                popupFig = uifigure('Name', 'Ollama Error', 'Position', [750, 340, 400, 300]);

                % Add the error labels to the popup window
                uilabel(popupFig, 'Position', [20 250 360 40],...
                    'Text', 'Ollama is not installed or not running.',...
                    'FontColor', [1 0 0]);

                uilabel(popupFig, 'Position', [20 200 360 40],...
                    'Text', 'Please install Ollama from:',...
                    'FontColor', [0 0 0]);

                uilabel(popupFig, 'Position', [20 170 360 40],...
                    'Text', '<a href="https://ollama.com/">https://ollama.com/</a>',...
                    'Interpreter', 'html');

                uilabel(popupFig, 'Position', [20 140 360 40],...
                    'Text', 'If installed, ensure Ollama is running.',...
                    'FontColor', [0.5 0.5 0.5]);



            end
        end
    end

    function createModelTab(tab, parentFig, settingsFig)
        grid = uigridlayout(tab, [12 2]);
        grid.RowHeight = repmat({'fit'}, 1, 12);
        grid.ColumnWidth = [120 350];
        grid.Padding = [10 10 10 10];

        % System Prompt
        uilabel(grid, 'Text', 'System Prompt:', 'VerticalAlignment', 'top');
        sysPromptArea = uitextarea(grid,...
            'Value', splitSystemPrompt(parentFig.UserData.systemPrompt),... % Modified line
            'Tag', 'systemPrompt');
        sysPromptArea.Layout.Row = [1 3];
        sysPromptArea.Layout.Column = 2;

        % Model Selection
        uilabel(grid, 'Text', 'Model:');
        [models, valid] = getOllamaModels(parentFig);
        if ~valid
            models = {'llama3.2-vision:latest'};
        end

        modelDropdown = uidropdown(grid,...
            'Items', models,...
            'Value', parentFig.UserData.model,...
            'Tag', 'modelSelector');
        modelDropdown.Layout.Row = 4;
        modelDropdown.Layout.Column = 2;

        % Model Parameters
        createParamControl(grid, 5, 'temperature', 'Temperature:', parentFig.UserData.modelOptions.temperature, 0, 1);
        createParamControl(grid, 6, 'top_p', 'Top P:', parentFig.UserData.modelOptions.top_p, 0, 1);
        createParamControl(grid, 7, 'top_k', 'Top K:', parentFig.UserData.modelOptions.top_k, 1, 100);
        createParamControl(grid, 8, 'num_ctx', 'Context Window:', parentFig.UserData.modelOptions.num_ctx, 512, 4096);
        createParamControl(grid, 9, 'num_predict', 'Max Tokens:', parentFig.UserData.modelOptions.num_predict, 1, 4096);
        createParamControl(grid, 10, 'seed', 'Seed:', parentFig.UserData.modelOptions.seed, 0, 99999);

        function createParamControl(parent, row, tag, label, value, minVal, maxVal)
            uilabel(parent, 'Text', label);
            controlGrid = uigridlayout(parent, [1 2],...
                'ColumnWidth', {'3x', '1x'},...
                'Tag', ['paramControl_' tag]);

            slider = uislider(controlGrid,...
                'Limits', [minVal maxVal],...
                'Value', value);
            spinner = uispinner(controlGrid,...
                'Limits', [minVal maxVal],...
                'Value', value,...
                'Step', 1);

            slider.ValueChangedFcn = @(src,~) set(spinner, 'Value', src.Value);
            spinner.ValueChangedFcn = @(src,~) set(slider, 'Value', src.Value);
        end
    end

    function saveAllSettings(parentFig, settingsFig)
        try
            % Capture original settings before changes
            originalSettings = struct(...
                'apiUrl', parentFig.UserData.apiUrl,...
                'httpOptions', parentFig.UserData.httpOptions,...
                'systemPrompt', parentFig.UserData.systemPrompt,...
                'model', parentFig.UserData.model,...
                'modelOptions', parentFig.UserData.modelOptions);

            % Get connection settings
            apiUrlField = findobj(settingsFig, 'Tag', 'apiUrl');
            timeoutField = findobj(settingsFig, 'Tag', 'timeoutSpinner');

            % Recreate HTTP options with explicit parameters
            parentFig.UserData.httpOptions = weboptions(...
                'MediaType', 'application/json',...
                'RequestMethod', 'post',...
                'ArrayFormat', 'json',...
                'Timeout', double(timeoutField.Value));

            % Update API URL
            parentFig.UserData.apiUrl = convertStringsToChars(apiUrlField.Value);

            % Get model components
            modelDropdown = findobj(settingsFig, 'Tag', 'modelSelector');
            sysPromptArea = findobj(settingsFig, 'Tag', 'systemPrompt');

            % Update model settings
            sysPromptValue = sysPromptArea.Value;
            if iscell(sysPromptValue)
                parentFig.UserData.systemPrompt = strjoin(sysPromptValue, '\n');
            else
                parentFig.UserData.systemPrompt = char(sysPromptValue);
            end
            parentFig.UserData.model = convertStringsToChars(modelDropdown.Value);

            % Update model parameters
            opts = parentFig.UserData.modelOptions;
            paramControls = findobj(settingsFig, '-regexp', 'Tag', 'paramControl');

            for i = 1:length(paramControls)
                tag = char(paramControls(i).Tag);
                value = double(paramControls(i).Children(2).Value);

                switch tag
                    case 'paramControl_temperature'
                        opts.temperature = value;
                    case 'paramControl_top_p'
                        opts.top_p = value;
                    case 'paramControl_top_k'
                        opts.top_k = value;
                    case 'paramControl_num_ctx'
                        opts.num_ctx = round(value);
                    case 'paramControl_num_predict'
                        opts.num_predict = round(value);
                    case 'paramControl_seed'
                        opts.seed = round(value);
                end
            end

            parentFig.UserData.modelOptions = opts;

            % Detect changes and build message
            changes = {};

            % Check API URL
            if ~strcmp(originalSettings.apiUrl, parentFig.UserData.apiUrl)
                changes{end+1} = sprintf('API URL → "%s"', parentFig.UserData.apiUrl);
            end


            % Check Timeout
            if originalSettings.httpOptions.Timeout ~= parentFig.UserData.httpOptions.Timeout
                changes{end+1} = sprintf('Timeout → %d seconds', parentFig.UserData.httpOptions.Timeout);
            end

            % Check System Prompt
            if ~strcmp(originalSettings.systemPrompt, parentFig.UserData.systemPrompt)
                changes{end+1} = sprintf('System Prompt → "%s"', parentFig.UserData.systemPrompt);
            end

            % Check Model
            if ~strcmp(originalSettings.model, parentFig.UserData.model)
                changes{end+1} = sprintf('Model → "%s"', parentFig.UserData.model);
            end

            % Check Model Options
            fields = {'temperature', 'top_p', 'top_k', 'num_ctx', 'num_predict', 'seed'};
            for i = 1:numel(fields)
                field = fields{i};
                originalVal = originalSettings.modelOptions.(field);
                newVal = parentFig.UserData.modelOptions.(field);
                if originalVal ~= newVal
                    changes{end+1} = sprintf('%s → %g', field, newVal);
                end
            end

            % Create notification message
            if isempty(changes)
                msg = 'Settings updated successfully (no changes detected)';
            else
                msg = ['Settings updated successfully:' newline];
                msg = [msg strjoin(cellfun(@(c) ['• ' c], changes, 'UniformOutput', false), newline)];
            end

            close(settingsFig);
            updateHistory('system', msg);

        catch ME
            uialert(settingsFig, ME.message, 'Save Error');
        end
    end

    function [models, valid] = getOllamaModels(parentFig, customUrl)
        valid = false;
        if nargin < 2
            customUrl = parentFig.UserData.apiUrl;
        end

        try
            % Create proper GET options while preserving original POST settings
            getOptions = weboptions(...
                'RequestMethod', 'get',...
                'Timeout', parentFig.UserData.httpOptions.Timeout,...
                'ContentType', 'json');

            apiUrl = strrep(customUrl, '/api/generate', '/api/tags');
            response = webread(apiUrl, getOptions);

            if isfield(response, 'models') && ~isempty(response.models)
                models = {response.models.name};
                models = unique(models, 'stable');
                valid = true;
                if isempty(models)
                    models = {'llama3.2-vision:latest'};
                    valid = false;
                end
            else
                models = {'llama3.2-vision:latest'};
            end
        catch
            models = {'llama3.2-vision:latest'};
        end
    end

    function closeSettings(src,~)
        delete(src);
    end

    function prompt = buildPrompt(messages)
        promptParts = cell(1, numel(messages));
        for i = 1:numel(messages)
            switch lower(messages(i).role)
                case 'system'
                    promptParts{i} = sprintf("System: %s", messages(i).content);
                case 'user'
                    promptParts{i} = sprintf("User: %s", messages(i).content);
                case 'assistant'
                    promptParts{i} = sprintf("Assistant: %s", messages(i).content);
            end
        end
        prompt = strjoin(string(promptParts), '\n');
    end

    function base64Image = encode_image(image_path)
        fid = fopen(image_path, 'rb');
        imageData = fread(fid, inf, '*uint8');
        fclose(fid);
        base64Image = matlab.net.base64encode(imageData);
    end

    function textContent = extractDocumentText(filePath)
        [~, ~, ext] = fileparts(filePath);
        textContent = 'Unsupported document format';
        try
            if strcmpi(ext, '.pdf') || strcmpi(ext, '.txt')
                textContent = extractFileText(filePath);
                textContent = char(textContent);
            elseif strcmpi(ext, '.docx')
                textContent = extractDocxText(filePath);
            end
        catch ME
            textContent = ['Error: ' ME.message];
        end
    end

    function text = extractDocxText(docxPath)
        tmpDir = tempname;
        mkdir(tmpDir);
        try
            unzip(docxPath, tmpDir);
            xmlPath = fullfile(tmpDir, 'word', 'document.xml');
            xmlText = fileread(xmlPath);
            tokens = regexp(xmlText, '<w:t[^>]*>([^<]*)</w:t>', 'tokens');
            text = strjoin([tokens{:}], ' ');
            rmdir(tmpDir, 's');
        catch ME
            text = ['DOCX Error: ' ME.message];
            try
                rmdir(tmpDir, 's');
            catch
            end
        end
    end

% Helper function to split system prompt into lines
    function lines = splitSystemPrompt(prompt)
        if ischar(prompt)
            lines = regexp(prompt, '\n', 'split');
        elseif isstring(prompt)
            lines = strsplit(prompt, newline);
        else
            lines = {''};
        end
    end
    function openHelpWindow()
        % Create Help Window
        helpFig = uifigure('Name', 'Help Guide', ...
            'Position', [200 300 700 600]);
        movegui(helpFig, 'center');

        % Create Scrollable Panel (no longer scrollable)
        scrollPanel = uipanel(helpFig, ...
            'Position', [0 0 700 600], ...
            'Scrollable', 'off'); % Disable scrolling for the panel

        % Build HTML content using sprintf for proper concatenation
        helpText = sprintf([...
            '<html><div style="font-family:Arial; padding:15px; line-height:1.6">',...
            '<h1 style="color:#2c3e50; border-bottom:2px solid #3498db">Help Guide for Local Ollama Chat Settings</h1>',...
            '<p>Welcome to the <b>Local Ollama Chat</b> help page! Here, you''ll find explanations for all adjustable parameters in the settings menu.</p>',...
            '<hr>',...
            '<h2 style="color:#2980b9">1. Connection Settings</h2>',...
            '<h3>API URL</h3>',...
            '<ul>',...
            '<li>This is the URL of the local API endpoint used for communication with the AI model</li>',...
            '<li>Default: <code>http://localhost:11434/api/generate</code></li>',...
            '<li>Change this only if you are using a different server or port</li>',...
            '</ul>',...
            '<h3>Timeout (seconds)</h3>',...
            '<ul>',...
            '<li>Sets the maximum time the system waits for a response before giving up</li>',...
            '<li>Default: <code>300</code> seconds (5 minutes)</li>',...
            '<li>Increase if you experience timeout errors with large requests</li>',...
            '</ul>',...
            '<hr>',...
            '<h2 style="color:#2980b9">2. Model Settings</h2>',...
            '<h3>System Prompt</h3>',...
            '<ul>',...
            '<li>A predefined instruction for the AI model to guide its behavior</li>',...
            '<li>Example: <code>"You are a helpful assistant."</code></li>',...
            '<li>Modify this if you want the AI to respond differently (e.g., <code>"You are a coding assistant."</code>)</li>',...
            '</ul>',...
            '<h3>Model Selection</h3>',...
            '<ul>',...
            '<li>Choose from available AI models</li>',...
            '<li>Default: <code>llama3.2-vision:latest</code></li>',...
            '<li>The list updates based on models available in your local API</li>',...
            '</ul>',...
            '<hr>',...
            '<h2 style="color:#2980b9">3. Model Parameters</h2>',...
            '<p>These parameters affect the AI''s response style and generation behavior.</p>',...
            '<h3>Temperature (<code>0 to 1</code>)</h3>',...
            '<ul>',...
            '<li>Controls randomness in responses</li>',...
            '<li>Lower values (<code>0.1 - 0.3</code>): More predictable and focused answers</li>',...
            '<li>Higher values (<code>0.7 - 1.0</code>): More creative and varied responses</li>',...
            '<li>Default: <code>0.5</code> (balanced output)</li>',...
            '</ul>',...
            '<h3>Top-P (Nucleus Sampling) (<code>0 to 1</code>)</h3>',...
            '<ul>',...
            '<li>Limits AI choices to the most probable tokens</li>',...
            '<li>Lower values (<code>0.1 - 0.3</code>): More deterministic responses</li>',...
            '<li>Higher values (<code>0.7 - 1.0</code>): More diverse responses</li>',...
            '<li>Default: <code>0.5</code></li>',...
            '</ul>',...
            '<h3>Top-K (<code>1 to 100</code>)</h3>',...
            '<ul>',...
            '<li>Similar to Top-P but limits token selection to the top <b>K</b> most likely words</li>',...
            '<li>Lower values (<code>10 - 20</code>): More focused responses</li>',...
            '<li>Higher values (<code>50 - 100</code>): More variation in responses</li>',...
            '<li>Default: <code>40</code></li>',...
            '</ul>',...
            '<h3>Context Window Size (<code>num_ctx</code>) (<code>512 to 4096</code>)</h3>',...
            '<ul>',...
            '<li>Determines how much text the AI can remember in a conversation</li>',...
            '<li>Higher values (<code>2048 - 4096</code>): Better long-term memory but more processing time</li>',...
            '<li>Default: <code>2048</code></li>',...
            '</ul>',...
            '<h3>Max Tokens (<code>num_predict</code>) (<code>1 to 4096</code>)</h3>',...
            '<ul>',...
            '<li>Limits the number of tokens (words/characters) generated per response</li>',...
            '<li>Lower values (<code>50 - 200</code>): Shorter responses</li>',...
            '<li>Higher values (<code>500+</code>): Longer and more detailed responses</li>',...
            '<li>Default: <code>128</code></li>',...
            '</ul>',...
            '<h3>Seed</h3>',...
            '<ul>',...
            '<li>Sets a fixed value for reproducible results</li>',...
            '<li><code>0</code>: No fixed seed, responses vary</li>',...
            '<li>Any other number: Ensures consistent AI output across runs</li>',...
            '<li>Default: <code>0</code></li>',...
            '</ul>',...
            '<hr>',...
            '<h2 style="color:#2980b9">4. Save and Apply Settings</h2>',...
            '<ul>',...
            '<li>After adjusting parameters, click <b>Save All</b> to apply changes</li>',...
            '<li>Adjust settings based on your needs for better performance and response quality</li>',...
            '</ul>',...
            '<hr>',...
            '<p style="text-align:center">If you have any questions, feel free to reach out! Happy chatting! 😊<br>',...
            '<a href="https://rockbench.ir/">rockbench.ir</a></p>',...
            '</div></html>']);

        % Create HTML component with proper wrapping
        helpHtml = uihtml(scrollPanel, ...
            'Position', [10 10 680 580], ... % Adjusted height to fit within the panel
            'HTMLSource', helpText);

        % Add JavaScript to scroll to the top after loading
        helpHtml.HTMLSource = [helpText, ...
            '<script>window.scrollTo(0, 0);</script>'];
    end

end