"""Test the exact guard used by the recorded live run, without running the harness."""
import ast,copy,unittest
from pathlib import Path

class NativeResourceBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source=Path(__file__).resolve().parent/'recorded_resource_guard.py'
        tree=ast.parse(source.read_text());function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='safe')
        namespace={};exec(compile(ast.Module(body=[function],type_ignores=[]),str(source),'exec'),namespace)
        cls.guard=staticmethod(namespace['safe'])
    def setUp(self):self.initial={'pressureCode':1,'availableProxyBytes':5*1024**3,'swapUsedBytes':0,'compressorBytes':0}
    def test_normal(self):self.assertIsNone(self.guard(self.initial,self.initial))
    def test_exact_reserve_boundary(self):self.assertIsNone(self.guard(dict(self.initial,availableProxyBytes=4*1024**3),self.initial))
    def test_one_byte_below_reserve(self):self.assertEqual(self.guard(dict(self.initial,availableProxyBytes=4*1024**3-1),self.initial),'host-reserve')
    def test_pressure_stops(self):self.assertEqual(self.guard(dict(self.initial,pressureCode=2),self.initial),'memory-pressure')
    def test_any_swap_growth_stops(self):self.assertEqual(self.guard(dict(self.initial,swapUsedBytes=1),self.initial),'swap-growth')
    def test_compression_boundary(self):self.assertIsNone(self.guard(dict(self.initial,compressorBytes=512*1024**2),self.initial))
    def test_excess_compression_stops(self):self.assertEqual(self.guard(dict(self.initial,compressorBytes=512*1024**2+1),self.initial),'compression-growth')
if __name__=='__main__':unittest.main()
