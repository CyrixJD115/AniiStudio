import importlib.util
from pathlib import Path
import unittest
import numpy as np


def load(name,file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


core=load('kernel','dxbc-reference-kernel.py');textures=load('textures','dxbc-reference-textures.py')
shader=Path(__file__).resolve().parent.parent/'Research/2026-10-23/terrain-bake-shader-inspection/XTerrainBakePhysicalPage-0-CSMainWithVT-0.asm'


class DXBCReferenceTextureTests(unittest.TestCase):
    def test_gather_order_matches_sm5_documented_counterclockwise_footprint(self):
        image=np.repeat(np.array([[[[1],[2]],[[3],[4]]]],dtype=np.float32),4,axis=3)
        binding=textures.Textures({0:[image]},{0:'clamp'})
        k=core.Kernel('gather4_indexable(texture2darray) r1.xyzw, l(0.5, 0.5, 0.0, 0.0), t0.xyzw, s0.x',[[0,0,0]],textures=binding)
        k.run();np.testing.assert_array_equal(k.registers[1].view(np.float32),[[3,4,2,1]])

    def test_linear_clamp_repeat_and_explicit_mip_interpolation(self):
        image=np.repeat(np.array([[[[0],[1]],[[2],[3]]]],dtype=np.float32),4,axis=3)
        small=np.full((1,1,1,4),8,dtype=np.float32)
        binding=textures.Textures({0:[image,small]},{0:'clamp',1:'repeat'})
        uv=np.array([[.5,.5,0,0]],dtype=np.float32)
        np.testing.assert_array_equal(binding.sample(0,uv,np.array([0]),'clamp'),[[1.5]*4])
        np.testing.assert_array_equal(binding.sample(0,uv,np.array([.5]),'clamp'),[[4.75]*4])
        uv[:,0]=1.25
        np.testing.assert_array_equal(binding.sample(0,uv,np.array([0]),'repeat'),[[1]*4])
        np.testing.assert_array_equal(binding.sample(0,uv,np.array([0]),'clamp'),[[2]*4])

    def test_complete_original_shader_runs_offline_with_explicit_constant_fixture(self):
        if not shader.exists():self.skipTest('Original terrain kernel unavailable')
        constants=np.zeros((19,4),dtype=np.float32);constants[0]=[1,1,0,0];constants[1]=[1,1,0,0];constants[2]=[1,1,0,0]
        words=constants.view(np.uint32);words[3:]=np.arange(256,dtype=np.uint8).view(np.uint32).reshape(16,4)
        buffers={6:(4,np.zeros(1,dtype=np.uint32))}
        for slot,row in [(7,[0,0,1/8,0]),(8,[0,0,1,0]),(9,[0,0,1,0])]:buffers[slot]=(16,np.array([row],dtype=np.float32).view(np.uint32))
        buffers[10]=(4,np.ones(256,dtype=np.float32).view(np.uint32))
        buffers[11]=(16,np.zeros((256,4),dtype=np.float32).view(np.uint32))
        buffers[12]=(16,np.ones((256,4),dtype=np.float32).view(np.uint32))
        buffers[13]=(4,np.zeros(256,dtype=np.float32).view(np.uint32))
        levels={i:[np.zeros((1,2,2,4),dtype=np.float32)] for i in range(6)}
        levels[4][0][:]=[.25,.36,.49,.8];levels[5][0][:]=[.5,.5,.5,.5]
        binding=textures.Textures(levels,{0:'clamp',1:'repeat'})
        threads=np.array([[x,y,0] for y in range(4) for x in range(4)],dtype=np.uint32)
        k=core.Kernel(shader.read_text(),threads,words,buffers,binding);result=k.run()
        self.assertEqual(set(result),{'u6','u7'})
        color=result['u7']['values'];self.assertTrue(np.all(np.isfinite(color)))
        np.testing.assert_allclose(color[:,:3],np.broadcast_to([.5,.6,.7],(16,3)),atol=.002)
        self.assertTrue(np.all(np.isfinite(result['u6']['values'])))


if __name__=='__main__':unittest.main()
