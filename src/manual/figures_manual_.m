%--------------------------------------------------------------------------
function S0 = figures_manual_(P)
    S0.csFig = {'FigPos', 'FigMap', 'FigTime', 'FigWav', 'FigWavCor', 'FigProj', 'FigCorr', 'FigIsi', 'FigHist'};

    if get_set_(P, 'fImportKsort', 0)
        ftShape = [.15 0 .85 .2];
        fcShape = [.85 .2 .15 .27];
        fiShape = [.85 .47 .15 .26];
        fhShape = [.85 .73 .15 .27];
        fwcTitle = ['KiloSort cluster similarity score (click): ', P.vcFile_prm];
    else
        ftShape = [.15 0 .7 .2];
        fcShape = [.85 .25 .15 .25];
        fiShape = [.85 .5 .15 .25];
        fhShape = [.85 .75 .15 .25];
        fwcTitle = ['Waveform correlation (click): ', P.vcFile_prm];

        % rho-delta plot
        S0.csFig{end+1} = 'FigRD';
        S0.hFigRD = create_figure_('FigRD', [.85 0 .15 .25], ['Cluster rho-delta: ', P.vcFile_prm]);
    end

    S0.hFigPos    = create_figure_('FigPos', [0 0 .15 .5], ['Unit position; ', P.vcFile_prm], 1, 0);
    S0.hFigMap    = create_figure_('FigMap', [0 .5 .15 .5], ['Probe map; ', P.vcFile_prm], 1, 0);
    S0.hFigWav    = create_figure_('FigWav', [.15 .2 .35 .8],['Averaged waveform: ', P.vcFile_prm], 0, 1);
    S0.hFigTime   = create_figure_('FigTime', ftShape, ['Time vs. Amplitude; (Sft)[Up/Down] channel; [h]elp; [a]uto scale; ', P.vcFile]);
    S0.hFigProj   = create_figure_('FigProj', [.5 .2 .35 .5], ['Feature projection: ', P.vcFile_prm]);
    S0.hFigWavCor = create_figure_('FigWavCor', [.5 .7 .35 .3], fwcTitle);
    S0.hFigHist   = create_figure_('FigHist', fhShape, ['ISI Histogram: ', P.vcFile_prm]);
    S0.hFigIsi    = create_figure_('FigIsi', fiShape, ['Return map: ', P.vcFile_prm]);
    S0.hFigCorr   = create_figure_('FigCorr', fcShape, ['Time correlation: ', P.vcFile_prm]);

    S0.cvrFigPos0 = cellfun(@(vc) get(get_fig_(vc), 'OuterPosition'), S0.csFig, 'UniformOutput', 0);
end %func
