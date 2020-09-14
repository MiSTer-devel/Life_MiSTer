import argparse
import logging
import os
import re
import sys
import math


def setup_parser():
    class Parser(argparse.ArgumentParser):
        def error(self, message):
            # Superclass only report error message.
            # Override to also show print help.
            self._print_message(('%s: error: %s\n\n') % (self.prog, message))
            self.print_help(sys.stderr)
            self.exit(2)

    parser = Parser(description = "convert a Conway's Game of Life rle file" \
                                  + " to an image file",
                    formatter_class = argparse.RawTextHelpFormatter,
                    )
    parser.add_argument('source',
                        help = 'path to rle file',
                        )
    parser.add_argument('target',
                        nargs = '?',
                        default = '',
                        help = "optional: path to image file, extension" \
                               + " determines image format",
                        )
    parser.add_argument('-s',
                        '--scale',
                        default = 1,
                        type = int,
                        help = 'scale factor',
                        metavar = 'scale',
                        )
    return parser


class Configuration:
    @staticmethod
    def read_configuration(config, comment_flag='#'):
        config_file = open(config)
        config_string = config_file.read()
        config_file.close()
        config_raw_lines = config_string.split('\n')
        config_lines = Configuration.clean_lines(config_raw_lines)
        return config_lines

    @staticmethod
    def clean_lines(lines, comment_flag='#'):
        def decomment(raw_line):
            return raw_line.partition(comment_flag)[0]
        def trim(raw_line):
            return raw_line.strip()
        def notempty(line):
            return line != ''

        decomment_lines = map(decomment, lines)
        trimmed_lines = map(trim, decomment_lines)
        nonempty_lines = filter(notempty, trimmed_lines)
        return nonempty_lines


class RLE(Configuration):
    def __init__(self, rle):
        dimensions_regex = r'x\s*=\s(\d+)\s*,\s*y\s*=\s(\d+)' # regex matches "x = #, y = #"

        def exit_unless(success):
            if not success: exit('Read RLE error.')

        lines = list(self.read_configuration(rle))

        match = re.search(dimensions_regex, lines[0])
        if match != None:
            x = int(match.group(1))
            y = int(match.group(2))
            self.dimensions = (x, y)
        else:
            exit_unless(False)

        self.specifications = ''.join(lines[1:])

    def next_sequence(self):
        specifications_regex = r'(\d*\$)|(!)|(\d*b)|(\d*o)' # regex matches #$, !, #b, #o

        match = re.search(specifications_regex, self.specifications)
        specification = match.group()
        self.specifications = self.specifications[len(specification):]
        if specification == '!':
            self.specifications = '!'
            return ('!', 0)
        else:
            if len(specification) == 1:
                specification = '1' + specification
            return (specification[-1], int(specification[0:-1]))


def get_paths(source, target):
    def exit_unless(success):
        if not success: exit('File error.')

    if os.path.isfile(source):
        (source_path, source_file) = os.path.split(source)
        (target_path, target_file) = os.path.split(target)

        if target_path == '':
            target_path = source_path

        if target_file == '':
            (source_root, _) = os.path.splitext(source_file)
            target_file = source_root + '.mem'

        target = os.path.join(target_path, target_file)
        return (source, target)
    else:
        exit_unless(False)

def membyte(alive, length):
    assert length < 128
    return ((int(alive) << 7) | length-1)

def membytes(alive, length):
    bts = bytearray()
    while length >= 128:
        length = length - 127
        bts.append(membyte(alive, 127))
    bts.append(membyte(alive, length))
    return bts

def actual_length(mem):
    output = []
    for char in mem:
        value, repeat = 255 * (char >> 7), (char & 0x7f)
        output.extend([value] * (repeat+1))
    return len(output)

def pad(row, target_length, rle_x=0):
    length = actual_length(row)
    print("length, target: ", length, target_length)
    assert (not rle_x or rle_x >= length)
    if rle_x:
        padded = membytes(False, (target_length - rle_x) // 2)
    else:
        padded = membytes(False, (target_length - length) // 2)
    padded.extend(row)
    length = actual_length(padded)
    padded.extend(membytes(False, target_length - length))
    print("padded length: ", actual_length(padded))
    return padded

def make_mem(source, target):
    rle = RLE(source)
    x, _ = rle.dimensions
    complete = bytearray()
    current_row = bytearray()
    (symbol, length) = rle.next_sequence()
    while symbol != '!':
        if symbol == '$':
            for _ in range(length):
                complete.extend(pad(current_row, 2200, rle_x=x))
                current_row = bytearray()
        elif symbol == 'b':
            current_row.extend(membytes(False, length))
        else:
            current_row.extend(membytes(True, length))
        (symbol, length) = rle.next_sequence()
    complete.extend(pad(current_row, 2200, rle_x=x))
    complete = pad(complete, 1125*2200)
    with open(target, "wb") as fb:
        fb.write(complete)
        fb.flush()


def main(argv):
    parser = setup_parser()
    parsed_args = parser.parse_args(argv)

    source = parsed_args.source
    target = parsed_args.target

    scale = parsed_args.scale
    if scale < 1:
        exit('Scale factor cannot be less than 1.')

    (source, target) =  get_paths(source, target)
    make_mem(source, target)


if __name__ == '__main__':
    main(sys.argv[1:])