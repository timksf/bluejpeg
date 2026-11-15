# Preserve the RTL and clock constraints while refining a marginal routed design
proc udp_setup_failed {} {
    set path [get_timing_paths -max_paths 1 -setup]
    if {![llength $path]} { error "Missing UDP setup timing paths" }
    return [expr {[get_property SLACK $path] < 0}]
}

proc udp_refine_timing {} {
    foreach step {
        {phys_opt_design -directive AggressiveExplore}
        {route_design -directive Explore}
        {phys_opt_design -directive AggressiveExplore}
    } {
        if {![udp_setup_failed]} { return }
        puts "UDP timing refinement: $step"
        {*}$step
    }
    if {[udp_setup_failed]} {
        # Reroute the worst endpoint net while retaining the rest of the design
        set path [get_timing_paths -max_paths 1 -setup]
        set endpoint [get_property ENDPOINT_PIN $path]
        set net [get_nets -of_objects $endpoint]
        if {[llength $net] != 1} { error "Missing critical UDP endpoint net" }
        puts "UDP timing refinement: rerouting $net"
        route_design -unroute -nets $net
        route_design -directive Explore
        phys_opt_design -directive AggressiveExplore
    }
}

udp_refine_timing
