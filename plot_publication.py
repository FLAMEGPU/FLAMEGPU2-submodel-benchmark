#! /usr/bin/env python3
import seaborn as sns
import pandas as pd
from matplotlib.ticker import FormatStrFormatter
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import matplotlib.image as mpimg
from matplotlib import patches as mpatches
import argparse
import pathlib


# Default DPI
DEFAULT_DPI = 300

# Default directory for visualisation images
DEFAULT_INPUT_DIR= "." #"./sample/data/v100-470.82.01/alpha.2-v100-11.0-beltsoff"
DEFAULT_OUTPUT_DIR = "." #"./sample/figures/v100-470.82.01/alpha.2-v100-11.0-beltsoff"
# Default directory for visualisation images
DEFAULT_VISUALISATION_DIR = "./sample/figures/visualisation"


# Drift csv filename from simulation output
RESOLUTION_CSV_FILENAME = "resolution_steps.csv"
SCALING_CSV_FILENAME = "performance_scaling.csv"
SCALING_STEP_CSV_FILENAME = "performance_scalingperStep.csv"

# Visualisation images used in the figure (4 required)
VISUALISATION_IMAGE_FILENAMES = ['0.png', '1.png', '50.png']
POP_COUNT_D_VALUES = [256, 512, 1024, 2048, 4096]



EXPECTED_INPUT_FILES = [RESOLUTION_CSV_FILENAME, SCALING_CSV_FILENAME, SCALING_STEP_CSV_FILENAME]

def cli():
    parser = argparse.ArgumentParser(description="Python script to generate figure from csv files")

    parser.add_argument(
        '-o', 
        '--output-dir', 
        type=str, 
        help='directory to output figures into.',
        default=DEFAULT_OUTPUT_DIR
    )
    parser.add_argument(
        '--dpi', 
        type=int, 
        help='DPI for output file',
        default=DEFAULT_DPI
    )

    parser.add_argument(
        '-i',
        '--input-dir', 
        type=str, 
        help='Input directory, containing the csv files',
        default=DEFAULT_INPUT_DIR
    )
    
    parser.add_argument(
        '-v',
        '--vis-dir', 
        type=str, 
        help="Input directory, containing the visualisation files",
        default=DEFAULT_VISUALISATION_DIR
    )
    
    args = parser.parse_args()
    return args

def validate_args(args):
    valid = True

    # If output_dir is passed, create it, error if can't create it.
    if args.output_dir is not None:
        p = pathlib.Path(args.output_dir)
        try:
            p.mkdir(exist_ok=True)
        except Exception as e:
            print(f"Error: Could not create output directory {p}: {e}")
            valid = False

    # DPI must be positive, and add a max.
    if args.dpi is not None:
        if args.dpi < 1:
            print(f"Error: --dpi must be a positive value. {args.dpi}")
            valid = False

    # Ensure that the input directory exists, and that all required input is present.
    if args.input_dir is not None:
        input_dir = pathlib.Path(args.input_dir) 
        if input_dir.is_dir():
            missing_files = []
            for required_file in EXPECTED_INPUT_FILES:
                required_file_path = input_dir / required_file
                if not required_file_path.is_file():
                    missing_files.append(required_file_path)
                    valid = False
            if len(missing_files) > 0:
                print(f"Error: {input_dir} does not contain required files:")
                for missing_file in missing_files:
                    print(f"  {missing_file}")
        else:
            print(f"Error: Invalid input_dir provided {args.input_dir}")
            valid = False
            
        # Ensure that the visualisation input directory exists, and that all required images are present.
    vis_dir = pathlib.Path(args.vis_dir) 
    if vis_dir.is_dir():
        missing_files = []
        for vis_filename in VISUALISATION_IMAGE_FILENAMES:
            vis_file_path = vis_dir / vis_filename
            if not vis_file_path.is_file():
                missing_files.append(vis_file_path)
                valid = False
        if len(missing_files) > 0:
            print(f"Error: {vis_dir} does not contain required files:")
            for missing_file in missing_files:
                print(f"  {missing_file}")
    else:
        print(f"Error: Invalid vis_dir provided {args.vis_dir}")
        valid = False
            

    return valid


def main():

    # Validate cli
    args = cli()
    valid_args = validate_args(args)
    if not valid_args:
        return False
            
    # Set figure theme
    sns.set_theme(style='white')
    
    # setup sub plot using mosaic layout
    gs_kw = dict(width_ratios=[1, 1, 1], height_ratios=[1, 1])
    f, ax = plt.subplot_mosaic([['p1', 'p2', 'p3'],
                                ['p4', 'p5', 'p6'],
                                ],
                                  gridspec_kw=gs_kw, figsize=(10, 5),
                                  constrained_layout=True)
    input_dir = pathlib.Path(args.input_dir)
    
    # POP COUNT
    df = pd.read_csv(input_dir/SCALING_STEP_CSV_FILENAME, sep=',', quotechar='"')
    df.columns = df.columns.str.strip()
    # Select subset of data for the plot
    df = df[df['grid_width'].isin(POP_COUNT_D_VALUES)]
    # Calculate the pop count as a percentage of the initial expected pop size
    df['expected_pop_count'] = df['pop_size']*df['p_occupation']
    df['pop_count_percent'] = df['pop_count'] / df['expected_pop_count'] * 100.0
    # Plot
    plot = sns.lineplot(data=df, x='step', y='pop_count_percent', hue='grid_width', ax=ax['p1'], legend='full')
    plot.set(xlabel='Step', ylabel='N as percent of $N_{init}$')
    # set formatting
    ax['p1'].set_title(label='A', loc='left', fontweight="bold")
    ax['p1'].legend(title='D')
    
    # RESOLUTION
    # Load per simulation step data into data frame (strip any white space)
    df = pd.read_csv(input_dir/RESOLUTION_CSV_FILENAME, sep=',', quotechar='"')
    df.columns = df.columns.str.strip()
    df['unresolved_percent'] = df['mean_unresolved_count'] / df['mean_pop_count'] * 100.0
    # Plot
    plot = sns.barplot(data=df, x='resolution_iterations', y='unresolved_percent', hue='p_occupation', ax=ax['p2'])
    plot.set(xlabel='Resolution Steps', ylabel='Unresolved as % of mean N')
    # set formatting
    ax['p2'].set_title(label='B', loc='left', fontweight="bold")
    ax['p2'].legend(title=r'$\rho$')

    
    # SCALING PEFORMANCE
    df = pd.read_csv(input_dir/SCALING_CSV_FILENAME, sep=',', quotechar='"')
    df.columns = df.columns.str.strip()
    # Plot
    plot = sns.lineplot(data=df, x='pop_size', y='s_step_mean', ax=ax['p3'])
    plot.set(xlabel='$D^2$', ylabel='Mean step time (s)')
    # set formatting
    ax['p3'].set_title(label='C', loc='left', fontweight="bold")
    
    
    # visualisation path
    visualisation_dir = pathlib.Path(args.vis_dir) 
    
    # Plot vis for time step = 0
    v1 = mpimg.imread(visualisation_dir / VISUALISATION_IMAGE_FILENAMES[0]) 
    ax['p4'].imshow(v1)
    ax['p4'].set_axis_off()
    ax['p4'].set_title(label='D', loc='left', fontweight="bold")
    
    # Plot vis for time step = 1
    v1 = mpimg.imread(visualisation_dir / VISUALISATION_IMAGE_FILENAMES[1]) 
    ax['p5'].imshow(v1)
    ax['p5'].set_axis_off()
    ax['p5'].set_title(label='E', loc='left', fontweight="bold")
    
    # Plot vis for time step = 50
    v1 = mpimg.imread(visualisation_dir / VISUALISATION_IMAGE_FILENAMES[2]) 
    ax['p6'].imshow(v1)
    ax['p6'].set_axis_off()
    ax['p6'].set_title(label='F', loc='left', fontweight="bold")
    
   
        
    # Save to image
    #f.tight_layout()
    output_dir = pathlib.Path(args.output_dir) 
    f.savefig(output_dir/"paper_figure.png", dpi=args.dpi) 
    f.savefig(output_dir/"paper_figure.pdf", format='pdf', dpi=args.dpi)
    
    #plt.show()


# Run the main method if this was not included as a module
if __name__ == "__main__":
    main()
