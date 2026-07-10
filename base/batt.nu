# Battery management
#
# Currently only working on Lenovo stuff

const checks = {
    lenovo: /sys/bus/platform/drivers/ideapad_acpi
}

def check_platform []: nothing -> oneof<string, nothing> {
    if ("/sys/bus/platform/drivers/ideapad_acpi" | path exists) { return lenovo }
}
