import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec=importlib.util.spec_from_file_location('reference_kernel',Path(__file__).with_name('dxbc-reference-kernel.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
shader=Path(__file__).resolve().parent.parent/'Research/2026-10-23/terrain-bake-shader-inspection/XTerrainBakePhysicalPage-0-CSMainWithVT-0.asm'


class DXBCReferenceKernelTests(unittest.TestCase):
    def test_absolute_thread_coordinates_survive_page_batch_boundaries(self):
        # The final short batch must use absolute page coordinates, not restart
        # its texture phase at zero on every memory-bounded invocation.
        width=137; count=width*133
        indices=np.arange(count,dtype=np.uint32)
        threads=np.column_stack([indices%width,indices//width,np.zeros(count,dtype=np.uint32)])
        code='''utof r0.xyzw, vThreadID.xyzw
mad r1.xyzw, r0.xyxy, l(0.125, 0.25, 0.5, 0.75), l(-0.03125)
frc r2.xyzw, r1.xyzw
'''
        whole=module.Kernel(code,threads);whole.run()
        chunks=[]
        for start in range(0,count,8192):
            batch=module.Kernel(code,threads[start:start+8192]);batch.run()
            chunks.append(batch.registers[2].copy())
        np.testing.assert_array_equal(np.concatenate(chunks),whole.registers[2])

    def test_destination_masks_use_corresponding_source_components(self):
        code='''mov r0.xyzw, l(1.0, 2.0, 3.0, 4.0)
add r0.zw, r0.xxxy, l(0.0, 0.0, 10.0, 20.0)
mov r1.xyzw, -r0.wzyx
'''
        k=module.Kernel(code,[[0,0,0]]);k.run()
        np.testing.assert_array_equal(k.registers[0].view(np.float32),[[1,2,11,22]])
        np.testing.assert_array_equal(k.registers[1].view(np.float32),[[-22,-11,-2,-1]])

    def test_actual_shader_packed_remap_resolves_every_byte_and_sentinel(self):
        if not shader.exists():self.skipTest('Original disassembled kernel unavailable')
        text=shader.read_text();start=text.index('ushr r8.xyzw, r7.xyzw')
        end=text.index('ld_structured_indexable',start)
        fragment=text[start:end]
        constants=np.zeros((19,4),dtype=np.uint32)
        constants[3:]=np.arange(256,dtype=np.uint8).view(np.uint32).reshape(16,4)
        k=module.Kernel(fragment,np.zeros((256,3),dtype=np.uint32),constants)
        k.registers[7]=np.repeat(np.arange(256,dtype=np.uint32)[:,None],4,axis=1)
        k.run();expected=np.arange(256,dtype=np.float32);expected[255]=0
        np.testing.assert_array_equal(k.registers[5,:,2].view(np.float32),expected)

    def test_structured_scalar_load_at_byte_offset8_and_float_conversion(self):
        values=np.array([[1,2,3,4],[5,6,7,8]],dtype=np.float32)
        code='''ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.w, vThreadID.x, l(8), t7.x
ftou r1.xyzw, r0.wwww
utof r2.xyzw, r1.xyzw
'''
        k=module.Kernel(code,[[0,0,0],[1,0,0]],buffers={7:(16,values.view(np.uint32))});k.run()
        np.testing.assert_array_equal(k.registers[0,:,3].view(np.float32),[3,7])
        np.testing.assert_array_equal(k.registers[2,:,0].view(np.float32),[3,7])

    def test_dot_saturation_and_signed_bit_operations(self):
        code='''dp2 r0.x, l(2.0, 3.0, 0.0, 0.0), l(4.0, 5.0, 0.0, 0.0)
add_sat r0.y, l(-0.5), l(0.25)
mov r1.xyzw, l(-8)
ishr r1.xyzw, r1.xyzw, l(2)
'''
        k=module.Kernel(code,[[0,0,0]]);k.run()
        self.assertEqual(k.registers[0,0,0].view(np.float32),23)
        self.assertEqual(k.registers[0,0,1].view(np.float32),0)
        self.assertEqual(k.registers[1,0,0].view(np.int32),-2)

    def test_complete_original_kernel_parses_and_unknown_instructions_fail(self):
        if not shader.exists():self.skipTest('Original kernel unavailable')
        instructions=module.parse_program(shader.read_text())
        self.assertGreater(len(instructions),600)
        self.assertEqual(sum(op=='gather4_indexable' for op,_,_ in instructions),5)
        with self.assertRaises(ValueError):module.parse_program('execute_arbitrary r0, r1')
        with self.assertRaises(ValueError):module.Kernel('mov r32.x, l(0)',[[0,0,0]]).run()
        with self.assertRaises(ValueError):module.Kernel('sample_l_indexable(texture2darray) r0, r1, t0, s0, l(0)',[[0,0,0]]).run()


if __name__=='__main__':unittest.main()
