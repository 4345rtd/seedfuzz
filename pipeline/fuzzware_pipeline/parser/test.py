from .parser import SVDParser
import argparse

def convert_svd_to_yaml(svd_path: str, yaml_path: str):
    """Convert the SVD file at the given path to a YAML file."""
    try:
        parser = SVDParser(svd_path)
        parser.parse()
        parser.to_yaml(yaml_path)
        print(f"Successfully converted {svd_path} to {yaml_path}")
    except FileNotFoundError as e:
        print(f"Error: {e}")
    except RuntimeError as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="Convert an SVD file to a YAML file.")
    parser.add_argument("svd_path", type=str, help="Path to the input SVD file.")
    parser.add_argument("yaml_path", type=str, help="Path to the output YAML file.")
    
    args = parser.parse_args()

    # Perform conversion
    convert_svd_to_yaml(args.svd_path, args.yaml_path)