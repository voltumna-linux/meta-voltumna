#!/usr/bin/env python3

import os
import string
import sys

class Template(string.Template):
    delimiter = "@"

class Environ():
    def __getitem__(self, name):
        val = os.environ[name]
        val = val.split()
        if len(val) > 1:
            val = ["%s" % x for x in val]
            val = ', '.join(val)
            val = '[%s]' % val
        elif val:
            val = "%s" % val.pop()
        return val

try:
    sysroot = os.environ['SDKTARGETSYSROOT']
    target = os.environ['TARGET_PREFIX'] + 'gnu'
except KeyError:
    print("Not in environment setup, bailing")
    sys.exit(1)

file = os.path.join(sysroot, 'usr/lib/rustlib/', 
        target, 'x86_64-voltumnasdk-linux-gnu.json')

with open(file) as in_file:
    template = in_file.read()
    output = Template(template).substitute(Environ())
    with open(file, "w") as out_file:
        out_file.write(output)
