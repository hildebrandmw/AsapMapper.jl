"""
Script to depickle frequency results from KiloCore measurements and convert
it to a plain-text format.
"""

import pickle
import re

import os
from os import listdir
from os.path import isfile, join

import json

#def decode_legacy(f, result_dict):


def get_voltage(f):
    """
    Extract the voltage from the file name.
    """
    m = re.search("\d\.\d+(?=V)",f)
    return m.group(0)

def read_directory():
    # Fine all pickle files in the pwd.
    pwd = os.getcwd()
    files = [f for f in listdir(pwd) if isfile(join(pwd,f)) and ".pickle" in f]
    # Store results by voltage.
    results = {}
    for file_name in files:
        # Deserialize the pickle file.
        f = open(file_name, "rb")
        d = pickle.load(f)
        f.close()
        # Make a subdict for this voltage.
        # If different measurement files have different encodings, may have to
        # include a mechanism to determine the encoding for each.
        these_results = {}
        for (k,v) in d[0].items():
            # Address is just the key value.
            addr = str(k)
            # Frequency requires a little unpacking.
            if type(v) == float:
                freq = v
            else:
                freq = v[(0,0)]

            # Make an entry in the result dict
            these_results[addr] = freq

        voltage = get_voltage(file_name)
        # Add frequency results to the results dictionary for this voltage
        results[voltage] = these_results

    # Serialize the final dictionary to JSON
    f = open("frequencies.json", "w")
    json.dump(results,f,indent=2)
    f.close()

read_directory()
