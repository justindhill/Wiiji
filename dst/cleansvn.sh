#!/bin/bash
find ../../ -type d -name ".svn" -print0 | xargs -0 rm -r
