'''
Printer model specifications.

No rights reserved.
License CC0-1.0-only: https://directory.fsf.org/wiki/License:CC0
'''

class Model():
    ''' A printer model
        `paper_width`: pixels per line for the model/paper
        `is_new_kind`: some models have new "start print" command and can understand compressed data.
                the algorithm isn't implemented in Cat-Printer yet, but this should be no harm.
        `problem_feeding`: didn't yet figure out MX05/MX06 bad behavior giving feed command, use workaround for them
    '''
    paper_width: int = 384
    is_new_kind: bool = False
    problem_feeding: bool = False

def isValidModel(name):
    return name and any(name.startswith(model) for model in Models)

class ModelRegistry(dict):
    """Registry for printer models with support for prefix-based lookup.

    PrinterDriver.connect() uses `Models.get(name, ...)` with an exact key match on
    the discovered Bluetooth name. Some printers advertise names that extend a
    known model prefix (e.g. `MXTP-01` for model `MXTP`). This registry overrides
    `get` so that when there is no exact key match, it falls back to the longest
    prefix key whose value has been registered.
    """

    def get(self, key, default=None):
        # Try exact match first to preserve existing behavior.
        if dict.__contains__(self, key):
            return dict.get(self, key, default)

        # Fallback: resolve by longest matching prefix.
        if isinstance(key, str):
            matches = [model for model in self.keys() if key.startswith(model)]
            if matches:
                best_match = max(matches, key=len)
                return dict.get(self, best_match, default)

        return default

Models = ModelRegistry()
# all known supported models
for name in '_ZZ00 GB01 GB02 GB03 GT01 MX05 MX06 MX08 MX09 MX10 MX11 PD01 YT01 SC03h MXTP'.split(' '):
    Models[name] = Model()

# that can receive compressed data
for name in 'GB03'.split(' '):
    Models[name].is_new_kind = True

# feed message isn't handled corrently in the codebase, and these models have problems with it
# TODO fix that piece of code
for name in 'MX05 MX06 MX08 MX09 MX10'.split(' '):
    Models[name].problem_feeding = True
