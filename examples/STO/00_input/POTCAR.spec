# POTCAR.spec - specification of the POTCAR you must build yourself.
# This is NOT a POTCAR. POTCAR files are proprietary material distributed
# under the VASP license and are never included in this repository.
# See docs/potcar_policy.md for the full policy.

potcar_family : PAW PBE (e.g. the potpaw_PBE.54 library shipped with VASP)

# Element order MUST match POSCAR line 6 exactly: Sr Ti O
# Recommended potentials (the "simplest available" rule; Sr has no plain
# entry in potpaw_PBE.54, so the semicore variant Sr_sv is used):
element_1 : Sr  ->  Sr_sv
element_2 : Ti  ->  Ti
element_3 : O   ->  O

# Build command (run on your machine, with your licensed library):
#   VASP_PP=/path/to/your/potpaw_PBE.54
#   cat "$VASP_PP/Sr_sv/POTCAR" "$VASP_PP/Ti/POTCAR" "$VASP_PP/O/POTCAR" > 00_input/POTCAR
#
# Verify the order afterwards:
#   grep TITEL 00_input/POTCAR
#   -> PAW_PBE Sr_sv ... / PAW_PBE Ti ... / PAW_PBE O ...
#
# The pipeline preflight re-checks this order against POSCAR automatically.
