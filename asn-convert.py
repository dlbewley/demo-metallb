#!/usr/bin/env python3
# asn-convert.py
# Convert ASdot notation to ASplain
# Usage: python3 asn-convert.py 65008.30448 
# FRR does not support ASdot notation when using 4 byte ASN, so it must be converted to ASplain
import argparse

def convert_asdot_to_asplain(asdot):
    # Split the dotted format into high and low parts
    high, low = map(int, asdot.split('.'))
    # Calculate the ASPlain value
    asplain = (high * 65536) + low
    return asplain

def main():
    parser = argparse.ArgumentParser(description='Convert ASdot notation to ASplain')
    parser.add_argument('asdot', help='ASN in dot notation (e.g., 65008.30448)')
    args = parser.parse_args()

    try:
        asplain = convert_asdot_to_asplain(args.asdot)
        print(f"ASPlain for {args.asdot} is {asplain}")
    except ValueError as e:
        print(f"Error: Please provide a valid ASdot notation (e.g., 65008.30448)")
        exit(1)

if __name__ == "__main__":
    main()
