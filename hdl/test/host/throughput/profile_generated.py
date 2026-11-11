#!/usr/bin/env python3
"""Observe main-clock rule calls and pre-edge FIFO state in a Bluesim model."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--encoder-path')
parser.add_argument('--frame-register')
parser.add_argument('--run', action='store_true', help='compile and run the observer against the original shared library')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
for path in args.source.iterdir():
    if path.is_file() and (path.suffix in ('.h', '.mem', '.hex') or path.name == 'out'):
        shutil.copy2(path, args.output / path.name)
model = (args.source / 'model_mkTestbench.cxx').read_text()
impl = (args.source / 'mkTestbench.cxx').read_text()
header = (args.source / 'mkTestbench.h').read_text()
rules = dict(re.findall(r'void MOD_mkTestbench::(RL_\w+)\(\)\n\{(.*?)(?=\nvoid |\Z)', impl, re.S))
main_schedule = re.search(r'static void schedule_posedge_CLK\(.*?(?=\nstatic void |\Z)', model, re.S).group()
prefixes = re.findall(r'MOD_Fifo<[^>]+> (INST_\w+_)f_du_pixels;', header)
if args.encoder_path is None:
    assert len(prefixes) == 1, prefixes
    args.encoder_path = prefixes[0]
if args.frame_register is None:
    if 'INST_testVec_0_i_dut_rg_frame;' in header:
        args.frame_register = 'INST_testVec_0_i_dut_rg_frame'
    else:
        active = re.findall(r'MOD_Reg<tUInt8> (INST_\w+_rg_active);', header)
        assert len(active) == 1, active
        args.frame_register = active[0]
prefix = args.encoder_path
rule_prefix = 'RL_' + prefix.removeprefix('INST_')
fifos = re.findall(r'MOD_Fifo<[^>]+> (' + prefix + r'\w+);', header)
fifos = [f for f in fifos if '_doc_' not in f and not any(x in f for x in ('csrs', 'f_mode', 'f_meta', 'f_comp'))]
events = {}
for fifo in fifos:
    consumers = [rule for rule, body in rules.items() if fifo + '.METH_deq()' in body and 'INST_top.' + rule + '();' in main_schedule]
    if consumers:
        events[fifo.removeprefix(prefix)] = consumers
for suffix in ('r_disp_to_duproc', 'i_du_proc_i_quant_r_table_req', 'i_du_proc_i_quant_r_quant', 'i_stuffer_r_accumulate', 'i_du_proc_1_mkConnectionGetPut', 'i_du_proc_3_mkConnectionGetPut'):
    name = rule_prefix + suffix
    assert name in rules, name
    if 'INST_top.' + name + '();' in main_schedule:
        events[suffix] = [name]
names = list(events)
for rule in set(sum(events.values(), [])):
    call = f'INST_top.{rule}();'
    assert model.count(call) == 1, rule
    indices = [str(i) for i, name in enumerate(names) if rule in events[name]]
    model = model.replace(call, '(' + ', '.join(f'profile_fire[{i}]=true' for i in indices) + ', ' + call[:-1] + ');')

n = len(names)
declarations = f'''
struct ProfileStat {{
    unsigned long long count=0, first=0, last=0, valid=0, blocked=0, full=0;
    unsigned long long gap[513]={{}};
}};
static ProfileStat profile_stat[{n}];
static unsigned long long profile_cycle=0;
static unsigned profile_frame=0;
static bool profile_active=false;
static unsigned long long profile_phase_idle[3][8]={{}};
static unsigned long long profile_du_gap[8193]={{}};
static unsigned long long profile_last_du=0;
static unsigned long long profile_packet_cycles[4]={{}}, profile_packet_idle[4]={{}};
'''
pos = model.index('static void schedule_posedge_CLK')
model = model[:pos] + declarations + model[pos:]
pre = [f'bool profile_fire[{n}]={{}};', f'bool profile_valid[{n}]={{}}, profile_full[{n}]={{}};', f'bool profile_now=INST_top.{args.frame_register}.METH_read();', f'unsigned profile_phase=INST_top.{prefix}rg_mcu_phase.METH_read();', f'unsigned profile_index=INST_top.{prefix}rg_du_pix.METH_read();', f'unsigned profile_state=INST_top.{prefix}rg_state.METH_read();', f'bool profile_input=INST_top.{prefix}f_du_pixels.METH_notEmpty();', f'bool profile_dct_ready=INST_top.{prefix}i_du_proc_f_dct.METH_notFull();', f'bool profile_mode_ready=INST_top.{prefix}i_du_proc_i_quant_f_mode.METH_notFull();', f'bool profile_comp_ready=INST_top.{prefix}i_rle_f_comp.METH_notFull();', f'bool profile_meta_ready=INST_top.{prefix}i_huff_f_meta.METH_notFull();']
for i, name in enumerate(names):
    if prefix + name in fifos:
        pre.append(f'profile_valid[{i}]=INST_top.{prefix}{name}.METH_notEmpty(); profile_full[{i}]=!INST_top.{prefix}{name}.METH_notFull();')
packet_state = 'INST_testVec_0_i_dut_i_packetizer_rg_state'
pre += [f'unsigned profile_packet_state=INST_top.{packet_state}.METH_read();' if packet_state in header else 'unsigned profile_packet_state=0;']
pre += ['if(profile_now) { profile_active=true; ++profile_cycle; } else if(profile_active) {', 'printf("PROFILE_FRAME %u %llu\\n",++profile_frame,profile_cycle);']
for i, name in enumerate(names):
    pre += [f'printf("PROFILE_STAT {name} count=%llu first=%llu last=%llu valid=%llu blocked=%llu full=%llu\\n",profile_stat[{i}].count,profile_stat[{i}].first,profile_stat[{i}].last,profile_stat[{i}].valid,profile_stat[{i}].blocked,profile_stat[{i}].full);', f'for(unsigned gap=1;gap<513;++gap) if(profile_stat[{i}].gap[gap]) printf("PROFILE_GAP {name} %u %llu\\n",gap,profile_stat[{i}].gap[gap]);']
pre += ['for(unsigned phase=0;phase<3;++phase) for(unsigned reason=0;reason<8;++reason) if(profile_phase_idle[phase][reason]) printf("PROFILE_IDLE %u %u %llu\\n",phase,reason,profile_phase_idle[phase][reason]);', 'for(unsigned gap=1;gap<8193;++gap) if(profile_du_gap[gap]) printf("PROFILE_DU_GAP %u %llu\\n",gap,profile_du_gap[gap]);', 'for(unsigned state=0;state<4;++state) printf("PROFILE_PACKET %u cycles=%llu du_idle=%llu\\n",state,profile_packet_cycles[state],profile_packet_idle[state]);', 'fflush(stdout);', f'for(unsigned i=0;i<{n};++i) profile_stat[i]=ProfileStat{{}};', 'for(auto &phase:profile_phase_idle) for(auto &count:phase) count=0;', 'for(auto &count:profile_du_gap) count=0;', 'for(auto &count:profile_packet_cycles) count=0;', 'for(auto &count:profile_packet_idle) count=0;', 'profile_last_du=0; profile_cycle=0; profile_active=false;', '}']
pos = model.index('\t if (INST_top.DEF_WILL_FIRE_RL_action_f_update')
model = model[:pos] + '\n' + '\n'.join(pre) + '\n' + model[pos:]
dispatch = names.index('r_disp_to_duproc')
post = ['if(profile_now) {', '++profile_packet_cycles[profile_packet_state];', f'for(unsigned i=0;i<{n};++i) {{', 'auto &s=profile_stat[i];', 'if(profile_fire[i]) { if(s.count) { auto gap=profile_cycle-s.last; ++s.gap[gap>512?512:gap]; } else s.first=profile_cycle; ++s.count; s.last=profile_cycle; }', 's.valid+=profile_valid[i]; s.blocked+=profile_valid[i]&&!profile_fire[i]; s.full+=profile_full[i];', '}', f'if(profile_fire[{dispatch}] && profile_index==0) {{ if(profile_last_du) {{ auto gap=profile_cycle-profile_last_du; ++profile_du_gap[gap>8192?8192:gap]; }} profile_last_du=profile_cycle; }}', f'if(profile_state==3 && !profile_fire[{dispatch}] && profile_stat[{dispatch}].count) {{', '++profile_packet_idle[profile_packet_state];', 'unsigned reason=!profile_input ? 0 : (!profile_dct_ready ? 1 : ((profile_index==0 && !profile_mode_ready) ? 2 : ((profile_index==0 && !profile_comp_ready) ? 3 : ((profile_index==0 && !profile_meta_ready) ? 4 : 5))));', 'if(profile_phase<3) ++profile_phase_idle[profile_phase][reason];', '}', '}']
pos = re.search(r'\n\t INST_top\.\w+\.clk\(', model).start()
model = model[:pos] + '\n' + '\n'.join(post) + '\n' + model[pos:]
(args.output / 'model_mkTestbench.cxx').write_text(model)
(args.output / 'profile_manifest.json').write_text(json.dumps(events, indent=2) + '\n')
print(f'Generated {n} observers in {args.output}')
if args.run:
    bsim = subprocess.run(['bluetcl'], input='puts $env(BLUESPECDIR)\n', text=True, capture_output=True, check=True).stdout.strip()
    output = args.output.resolve()
    source = args.source.resolve()
    subprocess.run(['c++', '-O3', '-fPIC', '-std=c++17', '-I' + str(Path(bsim) / 'Bluesim'), '-c', str(output / 'model_mkTestbench.cxx'), '-o', str(output / 'model_mkTestbench.o')], check=True)
    subprocess.run(['c++', '-shared', str(output / 'model_mkTestbench.o'), str(source / 'out.so'), '-Wl,-rpath,' + str(source), '-o', str(output / 'out.so')], check=True)
    with (output / 'profile.log').open('w') as log:
        subprocess.run(['./out'], cwd=output, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = (output / 'profile.log').read_text()
    if 'ERROR' in result or 'PASSED' not in result:
        raise RuntimeError('the observed simulation did not pass its reference checks')
    print(f'Completed simulation, results in {output / "profile.log"}')
