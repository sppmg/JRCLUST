function hFigs = doSpawnFigures(hCfg)
    %DOSPAWNFIGURES Create the standard cadre of figures
    [~, sessionName, ~] = fileparts(hCfg.configFile);
    hFigs = containers.Map();

    if hCfg.fImportKsort
        ftShape = [.15 0 .85 .2];
        fcShape = [.85 .2 .15 .27];
        fiShape = [.85 .47 .15 .26];
        fhShape = [.85 .73 .15 .27];
        fwcTitle = ['KiloSort cluster similarity score (click): ', sessionName];
    else
        ftShape = [.15 0 .7 .2];
        fcShape = [.85 .25 .15 .25];
        fiShape = [.85 .5 .15 .25];
        fhShape = [.85 .75 .15 .25];
        fwcTitle = ['Waveform correlation (click): ', sessionName];

        % rho-delta plot
        hFigs('hFigRD') = doCreateFigure('FigRD', [.85 0 .15 .25], ['Cluster rho-delta: ', sessionName]);
    end

    hFigs('hFigPos')    = doCreateFigure('FigPos', [0 0 .15 .5], ['Unit position; ', sessionName], 1, 0);
    hFigs('hFigMap')    = doCreateFigure('FigMap', [0 .5 .15 .5], ['Probe map; ', sessionName], 1, 0);
    hFigs('hFigWav')    = doCreateFigure('FigWav', [.15 .2 .35 .8],['Averaged waveform: ', sessionName], 0, 1);
    hFigs('hFigTime')   = doCreateFigure('FigTime', ftShape, ['Time vs. Amplitude; (Sft)[Up/Down] channel; [h]elp; [a]uto scale; ', hCfg.vcFile]);
    hFigs('hFigProj')   = doCreateFigure('FigProj', [.5 .2 .35 .5], ['Feature projection: ', sessionName]);
    hFigs('hFigWavCor') = doCreateFigure('FigWavCor', [.5 .7 .35 .3], fwcTitle);
    hFigs('hFigHist')   = doCreateFigure('FigHist', fhShape, ['ISI Histogram: ', sessionName]);
    hFigs('hFigIsi')    = doCreateFigure('FigIsi', fiShape, ['Return map: ', sessionName]);
    hFigs('hFigCorr')   = doCreateFigure('FigCorr', fcShape, ['Time correlation: ', sessionName]);

    % hFigs.cvrFigPos0 = cellfun(@(vc) get(get_fig_(vc), 'OuterPosition'), hFigs.csFig, 'UniformOutput', 0);
end
