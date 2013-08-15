import argument_parser, tables, strutils, parseutils, ouroboros, os

## Tool to create and append files to binaries.

const
  param_verbose = @["-v", "--verbose"]
  help_verbose = "Be verbose about actions and print performance statistics."

  param_help = @["-h", "--help"]
  help_help = "Displays commandline help and exits."

  param_version = @["-V", "--version"]
  help_version = "Displays the current version and exists."

  param_overwrite = @["-o", "--overwrite"]
  help_overwrite = "Adds the specified directories as appended data to the " &
    "binary overwriting any previous appended data."

  param_remove = @["-r", "--remove"]
  help_remove = "Removes any appended data from the binary."

  param_list = @["-l", "--list"]
  help_list = "Lists the appended data and its attributes."

var
  DID_USE_COMMAND = false
  VERBOSE = false


proc validate_unique_command(parameter: string;
    VALUE: var Tparsed_parameter): string =
  ## Validates unique commands.
  ##
  ## The command will be valid only it points to a valid file and no other
  ## command has been used previously.
  if DID_USE_COMMAND:
    return "Can't use more than a single command at the same time."
  DID_USE_COMMAND = true

  if not VALUE.str_val.exists_file:
    return VALUE.str_val & " doesn't seem to be a valid file."


proc process_commandline(): Tcommandline_results =
  ## Parses the commandline.
  ##
  ## Returns a Tcommandline_results with at least one positional parameter.
  var PARAMS: seq[Tparameter_specification] = @[]

  PARAMS.add(new_parameter_specification(PK_EMPTY,
    help_text = help_help, names = param_help))

  PARAMS.add(new_parameter_specification(PK_EMPTY,
    help_text = help_verbose, names = param_verbose))

  PARAMS.add(new_parameter_specification(PK_EMPTY,
    help_text = help_version, names = param_version))

  PARAMS.add(new_parameter_specification(PK_STRING,
    help_text = help_overwrite, names = param_overwrite,
    custom_validator = validate_unique_command))

  PARAMS.add(new_parameter_specification(PK_STRING,
    help_text = help_remove, names = param_remove,
    custom_validator = validate_unique_command))

  PARAMS.add(new_parameter_specification(PK_STRING,
    help_text = help_list, names = param_list,
    custom_validator = validate_unique_command))

  RESULT = parse(PARAMS)

  if RESULT.options.hasKey(PARAM_VERBOSE[0]):
    VERBOSE = true

  if RESULT.options.hasKey(PARAM_VERSION[0]):
    echo "Alchemy version " & ouroboros.version_str
    quit()

  for path_param in RESULT.positional_parameters:
    if not path_param.str_val.exists_dir:
      echo path_param.str_val & " does not seem to be a valid directory."
      quit(4)

  if RESULT.options.hasKey(param_overwrite[0]):
    if RESULT.positional_parameters.len < 1:
      echo "You need to pass the name of the directories you want to append."
      echo_help(PARAMS)
      quit(1)

  if not DID_USE_COMMAND:
    if RESULT.positional_parameters.len > 0:
      echo "Specified positional parameters, but no command?"
      echo_help(PARAMS)
      quit(2)
    else:
      echo "You need to specify a command."
      echo_help(PARAMS)
      quit(3)


proc remove_appended_data(filename: string) =
  ## Removes previously appended binary data from the specified file.
  ##
  ## If a serious error happens the proc will quit the process.
  let a = filename.getAppendedData
  if a.format == noData:
    echo "No appended data found in " & filename
    return

  if VERBOSE:
    echo "Removing " & $a.dataSize & " bytes of appended data from " & filename

  var
    BUF = new_string(int(a.contentSize))
    INPUT = open(filename, fm_read)
  let read_len = INPUT.read_buffer(addr(BUF[0]), int(a.contentSize))
  INPUT.close

  if read_len != a.contentSize:
    echo "Error reading bytes from binary! $1 vs $2" % [$read_len,
      $a.contentSize]
    quit(1)

  INPUT = open(filename, fm_write)
  finally: INPUT.close
  let written_bytes = INPUT.write_buffer(addr(BUF[0]), int(a.contentSize))
  if written_bytes != a.contentSize:
    echo "Error writing " & filename
    echo "Careful, the file might have been left in a corrupted state!"
    quit(1)

  if VERBOSE:
    echo "Left $1 bytes on $2" % [$a.contentSize, filename]


when isMainModule:
  let args = process_commandline()

  if args.options.hasKey(param_remove[0]):
    remove_appended_data(args.options[param_remove[0]].str_val)

  for param in args.positional_parameters:
    echo "Adding dir '" & param.str_val & "'"
